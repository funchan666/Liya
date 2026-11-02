-- A call belongs to exactly two authenticated community members. Media is never stored here.
create table public.liya_call_config (id boolean primary key default true check(id), enabled boolean not null default false);
insert into public.liya_call_config(id,enabled) values(true,false);
alter table public.liya_call_config enable row level security;
revoke all on public.liya_call_config from public,anon,authenticated;
grant select,update on public.liya_call_config to service_role;
create table public.liya_calls (
 id uuid primary key,
 caller_id uuid not null references public.liya_people(id) on delete cascade,
 callee_id uuid not null references public.liya_people(id) on delete cascade,
 kind text not null check(kind in ('audio','video')),
 status text not null check(status in ('ringing','accepted','ended')),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now() + interval '45 seconds'),
 updated_at timestamptz not null default now(),
 check(caller_id <> callee_id)
);
create index liya_calls_caller on public.liya_calls(caller_id,created_at desc);
create index liya_calls_callee on public.liya_calls(callee_id,created_at desc);
alter table public.liya_calls enable row level security;
revoke all on public.liya_calls from public, anon, authenticated;
grant select on public.liya_calls to authenticated;
create policy calls_participant_read on public.liya_calls for select to authenticated
 using ((select auth.uid()) in (caller_id,callee_id));

create function liya_social_private.call_create(p_id uuid, p_callee uuid, p_kind text)
returns public.liya_calls language plpgsql security definer set search_path='' as $$
declare me uuid := auth.uid(); result public.liya_calls; a text; b text;
begin
 if me is null or p_id is null or p_callee is null or me=p_callee or p_kind not in ('audio','video') then raise exception 'invalid call'; end if;
 if not exists(select 1 from public.liya_call_config where id=true and enabled) then raise exception 'calling unavailable'; end if;
 a:=least(me::text,p_callee::text); b:=greatest(me::text,p_callee::text);
 perform pg_advisory_xact_lock(hashtextextended('call-user:'||a,0));
 perform pg_advisory_xact_lock(hashtextextended('call-user:'||b,0));
 select * into result from public.liya_calls where id=p_id;
 if found then
  if result.caller_id<>me or result.callee_id<>p_callee or result.kind<>p_kind then raise exception 'request mismatch'; end if;
  return result;
 end if;
 if not exists(select 1 from public.liya_people where id=me) or not exists(select 1 from public.liya_people where id=p_callee)
    or liya_social_private.blocked(p_callee) then raise exception 'member unavailable'; end if;
 if (select count(*) from public.liya_calls where caller_id=me and created_at>now()-interval '1 minute') >= 5 then raise exception 'too many calls'; end if;
 update public.liya_calls set status='ended',updated_at=now()
 where status='ringing' and expires_at<=now() and (caller_id in (me,p_callee) or callee_id in (me,p_callee));
 update public.liya_calls set status='ended',updated_at=now()
 where status='accepted' and updated_at < now()-interval '2 minutes' and (caller_id in (me,p_callee) or callee_id in (me,p_callee));
 if exists(select 1 from public.liya_calls where status in ('ringing','accepted') and (caller_id in (me,p_callee) or callee_id in (me,p_callee))) then raise exception 'member busy'; end if;
 insert into public.liya_calls(id,caller_id,callee_id,kind,status) values(p_id,me,p_callee,p_kind,'ringing') returning * into result;
 return result;
end $$;
create function liya_social_private.call_transition(p_id uuid,p_action text)
returns public.liya_calls language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); result public.liya_calls;
begin
 if me is null then raise exception 'authentication required'; end if;
 select * into result from public.liya_calls where id=p_id and me in (caller_id,callee_id) for update;
 if not found then raise exception 'call unavailable'; end if;
 if result.status='ended' then return result; end if;
 if p_action='accept' then
  if me<>result.callee_id or result.status<>'ringing' or result.expires_at<=now() or liya_social_private.blocked(result.caller_id) then raise exception 'call unavailable'; end if;
  update public.liya_calls set status='accepted',updated_at=now() where id=p_id returning * into result;
 elsif p_action='end' then
  update public.liya_calls set status='ended',updated_at=now() where id=p_id returning * into result;
 elsif p_action='heartbeat' then
  if result.status<>'accepted' or result.updated_at<now()-interval '2 minutes' or liya_social_private.blocked(case when me=result.caller_id then result.callee_id else result.caller_id end) then raise exception 'call unavailable'; end if;
  update public.liya_calls set updated_at=now() where id=p_id returning * into result;
 else raise exception 'invalid action'; end if;
 return result;
end $$;
create function public.liya_call_create(p_id uuid,p_callee uuid,p_kind text) returns public.liya_calls
 language sql security invoker set search_path='' as $$ select * from liya_social_private.call_create(p_id,p_callee,p_kind); $$;
create function public.liya_call_transition(p_id uuid,p_action text) returns public.liya_calls
 language sql security invoker set search_path='' as $$ select * from liya_social_private.call_transition(p_id,p_action); $$;
revoke all on function liya_social_private.call_create(uuid,uuid,text),liya_social_private.call_transition(uuid,text),public.liya_call_create(uuid,uuid,text),public.liya_call_transition(uuid,text) from public,anon,authenticated;
grant execute on function liya_social_private.call_create(uuid,uuid,text),liya_social_private.call_transition(uuid,text),public.liya_call_create(uuid,uuid,text),public.liya_call_transition(uuid,text) to authenticated;
create function liya_social_private.call_changed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' or old.status is distinct from new.status then
  perform liya_social_private.touch_user_revision(new.caller_id); perform liya_social_private.touch_user_revision(new.callee_id);
 end if;
 return null;
end $$;
revoke all on function liya_social_private.call_changed() from public,anon,authenticated;
create trigger liya_call_changed after insert or update on public.liya_calls for each row execute function liya_social_private.call_changed();
create function liya_social_private.end_blocked_calls() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.liya_calls set status='ended',updated_at=now() where status in ('ringing','accepted')
 and ((caller_id=new.owner_id and callee_id=new.target_id) or (caller_id=new.target_id and callee_id=new.owner_id));
 return null;
end $$;
revoke all on function liya_social_private.end_blocked_calls() from public,anon,authenticated;
create trigger liya_block_ends_calls after insert on public.liya_blocks for each row execute function liya_social_private.end_blocked_calls();
