-- Keep temporarily suspended background calls from expiring after two minutes.
create or replace function liya_social_private.call_create(p_id uuid, p_callee uuid, p_kind text)
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
 where status='accepted' and updated_at < now()-interval '30 minutes' and (caller_id in (me,p_callee) or callee_id in (me,p_callee));
 if exists(select 1 from public.liya_calls where status in ('ringing','accepted') and (caller_id in (me,p_callee) or callee_id in (me,p_callee))) then raise exception 'member busy'; end if;
 insert into public.liya_calls(id,caller_id,callee_id,kind,status) values(p_id,me,p_callee,p_kind,'ringing') returning * into result;
 return result;
end $$;
create or replace function liya_social_private.call_transition(p_id uuid,p_action text)
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
  if result.status<>'accepted' or result.updated_at<now()-interval '30 minutes' or liya_social_private.blocked(case when me=result.caller_id then result.callee_id else result.caller_id end) then raise exception 'call unavailable'; end if;
  update public.liya_calls set updated_at=now() where id=p_id returning * into result;
 else raise exception 'invalid action'; end if;
 return result;
end $$;
