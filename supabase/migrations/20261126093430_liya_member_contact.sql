create function public.liya_can_contact(p_peer uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select p_peer is not null and (select auth.uid()) is not null and p_peer <> (select auth.uid())
    and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
    and (select liya_social_private.account_active())
    and liya_social_private.profile_visible((select auth.uid()))
    and liya_social_private.profile_visible(p_peer)
    and exists (select 1 from public.liya_follows where owner_id = (select auth.uid()) and target_id = p_peer)
    and exists (select 1 from public.liya_follows where owner_id = p_peer and target_id = (select auth.uid()));
$$;
revoke all on function public.liya_can_contact(uuid) from public, anon;
grant execute on function public.liya_can_contact(uuid) to authenticated;

create or replace function liya_social_private.require_mutual_follow()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  sender uuid;
  recipient uuid;
  directions integer;
begin
  if tg_table_name = 'liya_messages' then
    sender := new.sender_id;
    recipient := new.recipient_id;
  else
    if tg_op = 'UPDATE' then
      if new.status <> 'accepted' or old.status = 'accepted' then return new; end if;
    end if;
    sender := new.caller_id;
    recipient := new.callee_id;
  end if;
  if coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'true'
    or exists (select 1 from liya_social_private.hidden_profiles where owner_id in (sender, recipient))
    or exists (select 1 from public.liya_blocks
      where (owner_id = sender and target_id = recipient) or (owner_id = recipient and target_id = sender)) then
    raise exception 'LIYA_MUTUAL_FOLLOW_REQUIRED' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    select count(*) into directions from (
      select owner_id from public.liya_follows
      where (owner_id = sender and target_id = recipient) or (owner_id = recipient and target_id = sender)
      order by owner_id for key share
    ) locked_follows;
  else
    select count(*) into directions from public.liya_follows
      where (owner_id = sender and target_id = recipient) or (owner_id = recipient and target_id = sender);
  end if;
  if directions <> 2 then
    raise exception 'LIYA_MUTUAL_FOLLOW_REQUIRED' using errcode = '42501';
  end if;
  return new;
end;
$$;

create function liya_social_private.end_unfollowed_calls()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.liya_calls set status = 'ended', updated_at = now()
    where status in ('ringing', 'accepted') and (
      (caller_id = old.owner_id and callee_id = old.target_id)
      or (caller_id = old.target_id and callee_id = old.owner_id)
    );
  return null;
end;
$$;
revoke all on function liya_social_private.end_unfollowed_calls() from public, anon, authenticated;
create trigger liya_unfollow_ends_calls after delete on public.liya_follows
  for each row execute function liya_social_private.end_unfollowed_calls();

create table liya_social_private.reported_message_snapshots (
  report_id uuid primary key references public.liya_social_reports(id) on delete cascade,
  message_id uuid not null,
  body text not null,
  media_paths text[] not null,
  media_kinds text[] not null
);
alter table liya_social_private.reported_message_snapshots enable row level security;
revoke all on liya_social_private.reported_message_snapshots from public, anon, authenticated;

create function liya_social_private.report_received_message(p_report_id uuid, p_message_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  reporter uuid := auth.uid();
  message public.liya_messages;
  request_id uuid;
begin
  if reporter is null or not liya_social_private.account_active()
     or coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'true' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_report_id is null or p_message_id is null or p_reason is null then
    raise exception 'Missing report details' using errcode = '22023';
  end if;
  select r.id into request_id from public.liya_social_reports r
    join liya_social_private.reported_message_snapshots s on s.report_id = r.id
    where r.id = p_report_id and r.reporter_id = reporter and r.reason = p_reason and s.message_id = p_message_id;
  if found then return request_id; end if;

  select * into message from public.liya_messages
    where id = p_message_id and recipient_id = reporter and sender_id <> reporter;
  if not found then raise exception 'Message unavailable' using errcode = '42501'; end if;
  insert into public.liya_social_reports(id, reporter_id, target_user, reason)
    values(p_report_id, reporter, message.sender_id, p_reason)
    on conflict(id) do nothing returning id into request_id;
  if found then
    insert into liya_social_private.reported_message_snapshots(report_id, message_id, body, media_paths, media_kinds)
      values(request_id, message.id, message.body, message.media_paths, message.media_kinds);
    return request_id;
  end if;
  select r.id into strict request_id from public.liya_social_reports r
    join liya_social_private.reported_message_snapshots s on s.report_id = r.id
    where r.id = p_report_id and r.reporter_id = reporter and r.reason = p_reason and s.message_id = p_message_id;
  return request_id;
end;
$$;
revoke all on function liya_social_private.report_received_message(uuid, uuid, text) from public, anon;
grant execute on function liya_social_private.report_received_message(uuid, uuid, text) to authenticated;
create function public.liya_report_message(p_report_id uuid, p_message_id uuid, p_reason text)
returns uuid language sql security invoker set search_path = '' as $$
  select liya_social_private.report_received_message(p_report_id, p_message_id, p_reason);
$$;
revoke all on function public.liya_report_message(uuid, uuid, text) from public, anon;
grant execute on function public.liya_report_message(uuid, uuid, text) to authenticated;
