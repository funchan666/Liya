-- Do not access OLD/NEW on the trigger operation where that row is unavailable.
create or replace function liya_social_private.call_changed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if old.status is not distinct from new.status then return null; end if;
 end if;
 perform liya_social_private.touch_user_revision(new.caller_id);
 perform liya_social_private.touch_user_revision(new.callee_id);
 return null;
end $$;
create or replace function liya_social_private.enqueue_call_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status <> 'accepted' then return null; end if;
 if tg_op='UPDATE' then
  if new.status <> 'ended' then return null; end if;
 end if;
 insert into public.liya_call_cleanup_jobs(call_id,caller_id,callee_id)
  values(old.id,old.caller_id,old.callee_id) on conflict(call_id) do nothing;
 perform liya_social_private.dispatch_call_cleanup(old.id);
 return null;
end $$;
