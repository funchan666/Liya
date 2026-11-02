-- Only the delivery function can read device tokens or dispatch capabilities.
create table public.liya_voip_config (id boolean primary key default true check(id), enabled boolean not null default false);
insert into public.liya_voip_config(id,enabled) values(true,false);
alter table public.liya_voip_config enable row level security;
revoke all on public.liya_voip_config from public,anon,authenticated;
grant select,update on public.liya_voip_config to service_role;
create table public.liya_voip_devices (
 token text primary key check(token ~ '^[0-9a-f]{32,256}$'),
 owner_id uuid not null references auth.users(id) on delete cascade,
 environment text not null check(environment in ('sandbox','production')),
 bundle_id text not null check(char_length(bundle_id) between 3 and 200),
 updated_at timestamptz not null default now()
);
create index liya_voip_devices_owner on public.liya_voip_devices(owner_id);
alter table public.liya_voip_devices enable row level security;
revoke all on public.liya_voip_devices from public,anon,authenticated;
grant select,insert,update,delete on public.liya_voip_devices to service_role;
create table public.liya_voip_jobs (
 call_id uuid primary key references public.liya_calls(id) on delete cascade,
 capability text not null default encode(extensions.gen_random_bytes(32),'hex'),
 next_attempt timestamptz not null default now(),
 attempts integer not null default 0,
 delivered_at timestamptz
);
alter table public.liya_voip_jobs enable row level security;
revoke all on public.liya_voip_jobs from public,anon,authenticated;
grant select,update on public.liya_voip_jobs to service_role;
create index liya_voip_jobs_due on public.liya_voip_jobs(next_attempt) where delivered_at is null;
create function liya_social_private.dispatch_voip(p_call uuid) returns void language plpgsql security definer set search_path='' as $$
declare j public.liya_voip_jobs;
begin
 if not exists(select 1 from public.liya_voip_config where id and enabled) then return; end if;
 select * into j from public.liya_voip_jobs where call_id=p_call and delivered_at is null and next_attempt<=now() for update skip locked;
 if not found then return; end if;
 if not exists(select 1 from public.liya_calls where id=p_call and status='ringing' and expires_at>now()) then return; end if;
 update public.liya_voip_jobs set next_attempt=now()+interval '30 seconds',attempts=attempts+1 where call_id=p_call;
 perform net.http_post(url:='https://hymfjhuglaqoftrcxfjx.supabase.co/functions/v1/liya-voip-delivery',
  headers:='{"Content-Type":"application/json","apikey":"sb_publishable_taByCR_N24fMyWxw4aFUqw_eZMldttB"}'::jsonb,
  body:=jsonb_build_object('call_id',j.call_id,'capability',j.capability),timeout_milliseconds:=25000);
exception when others then null;
end $$;
revoke all on function liya_social_private.dispatch_voip(uuid) from public,anon,authenticated;
create function liya_social_private.enqueue_voip() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.liya_voip_jobs(call_id) values(new.id) on conflict(call_id) do nothing;
 perform liya_social_private.dispatch_voip(new.id);
 return null;
end $$;
revoke all on function liya_social_private.enqueue_voip() from public,anon,authenticated;
create trigger liya_voip_enqueue after insert on public.liya_calls for each row execute function liya_social_private.enqueue_voip();
create function liya_social_private.retry_voip() returns void language plpgsql security definer set search_path='' as $$
declare j record;
begin
 if not exists(select 1 from public.liya_voip_config where id and enabled) then return; end if;
 for j in select v.call_id from public.liya_voip_jobs v join public.liya_calls c on c.id=v.call_id
  where v.delivered_at is null and v.next_attempt<=now() and c.status='ringing' and c.expires_at>now() order by v.next_attempt limit 25 loop
  perform liya_social_private.dispatch_voip(j.call_id);
 end loop;
end $$;
revoke all on function liya_social_private.retry_voip() from public,anon,authenticated;
select cron.schedule('liya-voip-delivery','10 seconds',$job$select liya_social_private.retry_voip();$job$);
select cron.alter_job((select jobid from cron.job where jobname='liya-voip-delivery'),active:=false);
