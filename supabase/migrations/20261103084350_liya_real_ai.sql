-- Real AI conversations are separate from the earlier scripted-reply history.
-- The old rows remain stored; no legacy reply is presented as a model response.
create table if not exists public.liya_ai_messages (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  role text not null check (role in ('user', 'assistant')),
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now(),
  unique (owner_id, request_id, role)
);
create index if not exists liya_ai_messages_owner_time on public.liya_ai_messages(owner_id, created_at, id);
alter table public.liya_ai_messages enable row level security;
revoke all on public.liya_ai_messages from public, anon, authenticated;
grant select on public.liya_ai_messages to authenticated;
grant all on public.liya_ai_messages to service_role;
create policy liya_ai_messages_owner_read on public.liya_ai_messages for select to authenticated
  using (owner_id = (select auth.uid()));

create table if not exists liya_social_private.ai_requests (
  owner_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  body text not null check (char_length(body) between 1 and 2000),
  state text not null check (state in ('pending', 'completed', 'failed')),
  lease uuid not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (owner_id, request_id)
);
create table if not exists liya_social_private.ai_attempts (
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists liya_ai_attempts_time on liya_social_private.ai_attempts(created_at);
create index if not exists liya_ai_attempts_owner_time on liya_social_private.ai_attempts(owner_id, created_at);
alter table liya_social_private.ai_requests enable row level security;
alter table liya_social_private.ai_attempts enable row level security;
revoke all on liya_social_private.ai_requests, liya_social_private.ai_attempts from public, anon, authenticated;

create or replace function public.liya_ai_claim(p_owner uuid, p_request uuid, p_body text, p_lease uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare existing liya_social_private.ai_requests%rowtype; cleaned text := btrim(p_body); now_at timestamptz := clock_timestamp();
begin
  if p_owner is null or p_request is null or p_lease is null or cleaned is null or char_length(cleaned) not between 1 and 2000 then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- Serialize admission so per-user and project-wide quotas cannot race.
  perform pg_advisory_xact_lock(hashtextextended('liya_ai_quota', 0));
  select * into existing from liya_social_private.ai_requests where owner_id = p_owner and request_id = p_request for update;
  if found then
    if existing.body <> cleaned then return jsonb_build_object('status', 'mismatch'); end if;
    if existing.state = 'completed' then return jsonb_build_object('status', 'completed'); end if;
    if existing.state = 'pending' and existing.updated_at > now_at - interval '60 seconds' then
      return jsonb_build_object('status', 'busy');
    end if;
  end if;
  if exists(select 1 from liya_social_private.ai_requests where owner_id = p_owner and request_id <> p_request and state = 'pending' and updated_at > now_at - interval '60 seconds') then
    return jsonb_build_object('status', 'busy');
  end if;
  delete from liya_social_private.ai_attempts where created_at < now_at - interval '2 days';
  if (select count(*) from liya_social_private.ai_attempts where owner_id = p_owner and created_at > now_at - interval '1 minute') >= 6
     or (select count(*) from liya_social_private.ai_attempts where owner_id = p_owner and created_at > now_at - interval '1 day') >= 60
     or (select count(*) from liya_social_private.ai_attempts where created_at > now_at - interval '1 day') >= 600 then
    return jsonb_build_object('status', 'rate_limited');
  end if;
  insert into liya_social_private.ai_attempts(owner_id) values (p_owner);
  insert into liya_social_private.ai_requests(owner_id, request_id, body, state, lease, updated_at)
    values (p_owner, p_request, cleaned, 'pending', p_lease, now_at)
    on conflict (owner_id, request_id) do update set state = 'pending', lease = excluded.lease, updated_at = excluded.updated_at;
  return jsonb_build_object('status', 'claimed');
end $$;

create or replace function public.liya_ai_finish(p_owner uuid, p_request uuid, p_lease uuid, p_reply text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare original text; now_at timestamptz := clock_timestamp();
begin
  if p_reply is null or char_length(btrim(p_reply)) not between 1 and 3000 then return false; end if;
  update liya_social_private.ai_requests set state = 'completed', updated_at = now_at
    where owner_id = p_owner and request_id = p_request and state = 'pending' and lease = p_lease
    returning body into original;
  if not found then return false; end if;
  insert into public.liya_ai_messages(owner_id, request_id, role, body, created_at) values
    (p_owner, p_request, 'user', original, now_at),
    (p_owner, p_request, 'assistant', btrim(p_reply), now_at + interval '1 millisecond');
  return true;
end $$;

create or replace function public.liya_ai_fail(p_owner uuid, p_request uuid, p_lease uuid)
returns void language sql security definer set search_path = '' as $$
  update liya_social_private.ai_requests set state = 'failed', updated_at = clock_timestamp()
  where owner_id = p_owner and request_id = p_request and state = 'pending' and lease = p_lease;
$$;
revoke all on function public.liya_ai_claim(uuid,uuid,text,uuid), public.liya_ai_finish(uuid,uuid,uuid,text), public.liya_ai_fail(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function public.liya_ai_claim(uuid,uuid,text,uuid), public.liya_ai_finish(uuid,uuid,uuid,text), public.liya_ai_fail(uuid,uuid,uuid) to service_role;

-- Remove the production scripted-reply entry point without deleting old data.
revoke execute on function public.liya_auto_send(uuid,text) from public, anon, authenticated;
revoke execute on function liya_social_private.auto_send(uuid,text) from public, anon, authenticated;
