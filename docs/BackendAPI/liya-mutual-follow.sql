-- Enforce mutual follows for new messages and call invitations or acceptance.
-- Existing messages and already connected calls are not removed or interrupted.
create or replace function liya_social_private.require_mutual_follow()
returns trigger language plpgsql security definer set search_path = '' as $$
declare a uuid; b uuid;
begin
 if tg_table_name = 'liya_messages' then
  a := new.sender_id; b := new.recipient_id;
 elsif tg_table_name = 'liya_calls' then
  if tg_op = 'UPDATE' then
   if new.status <> 'accepted' or old.status = 'accepted' then return new; end if;
  end if;
  a := new.caller_id; b := new.callee_id;
 else
  raise exception 'invalid mutual-follow trigger';
 end if;
 if not exists (select 1 from public.liya_follows where owner_id = a and target_id = b)
    or not exists (select 1 from public.liya_follows where owner_id = b and target_id = a) then
  raise exception 'LIYA_MUTUAL_FOLLOW_REQUIRED' using errcode = '42501';
 end if;
 return new;
end $$;

revoke all on function liya_social_private.require_mutual_follow() from public, anon, authenticated;
create trigger liya_messages_require_mutual before insert on public.liya_messages
 for each row execute function liya_social_private.require_mutual_follow();
create trigger liya_calls_require_mutual before insert or update of status on public.liya_calls
 for each row execute function liya_social_private.require_mutual_follow();
