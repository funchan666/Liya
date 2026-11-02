create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- A job is created transactionally whenever an accepted call ends or is deleted.
-- Capabilities stay in the restricted job table and the private pg_net queue.
create table public.liya_call_cleanup_jobs (
 call_id uuid primary key,
 caller_id uuid not null,
 callee_id uuid not null,
 capability text not null default encode(extensions.gen_random_bytes(32),'hex'),
 created_at timestamptz not null default now(),
 next_attempt timestamptz not null default now(),
 attempts integer not null default 0,
 completed_at timestamptz
);
alter table public.liya_call_cleanup_jobs enable row level security;
revoke all on public.liya_call_cleanup_jobs from public,anon,authenticated;
grant select,update on public.liya_call_cleanup_jobs to service_role;
create index liya_call_cleanup_due on public.liya_call_cleanup_jobs(next_attempt) where completed_at is null;

create function liya_social_private.dispatch_call_cleanup(p_call uuid) returns void
language plpgsql security definer set search_path='' as $$
declare job public.liya_call_cleanup_jobs;
begin
 select * into job from public.liya_call_cleanup_jobs where call_id=p_call and completed_at is null and next_attempt<=now() for update skip locked;
 if not found then return; end if;
 update public.liya_call_cleanup_jobs set attempts=attempts+1,next_attempt=now()+interval '1 minute' where call_id=p_call;
 perform net.http_post(
  url:='https://hymfjhuglaqoftrcxfjx.supabase.co/functions/v1/liya-call-cleanup',
  headers:='{"Content-Type":"application/json","apikey":"sb_publishable_taByCR_N24fMyWxw4aFUqw_eZMldttB"}'::jsonb,
  body:=jsonb_build_object('call_id',job.call_id,'capability',job.capability),
  timeout_milliseconds:=25000
 );
exception when others then
 -- Do not roll back the user's hangup or block: the scheduled worker will retry.
 null;
end $$;
revoke all on function liya_social_private.dispatch_call_cleanup(uuid) from public,anon,authenticated;

create function liya_social_private.enqueue_call_cleanup() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.status='accepted' and (tg_op='DELETE' or new.status='ended') then
  insert into public.liya_call_cleanup_jobs(call_id,caller_id,callee_id)
    values(old.id,old.caller_id,old.callee_id) on conflict(call_id) do nothing;
  perform liya_social_private.dispatch_call_cleanup(old.id);
 end if;
 return null;
end $$;
revoke all on function liya_social_private.enqueue_call_cleanup() from public,anon,authenticated;
create trigger liya_call_cleanup_update after update of status on public.liya_calls for each row execute function liya_social_private.enqueue_call_cleanup();
create trigger liya_call_cleanup_delete after delete on public.liya_calls for each row execute function liya_social_private.enqueue_call_cleanup();

create function liya_social_private.retry_call_cleanup() returns void
language plpgsql security definer set search_path='' as $$
declare item record;
begin
 for item in select call_id from public.liya_call_cleanup_jobs where completed_at is null and next_attempt<=now() order by next_attempt limit 25 loop
  perform liya_social_private.dispatch_call_cleanup(item.call_id);
 end loop;
 delete from public.liya_call_cleanup_jobs where completed_at < now()-interval '24 hours';
end $$;
revoke all on function liya_social_private.retry_call_cleanup() from public,anon,authenticated;
select cron.schedule('liya-call-cleanup','* * * * *',$job$select liya_social_private.retry_call_cleanup();$job$);
