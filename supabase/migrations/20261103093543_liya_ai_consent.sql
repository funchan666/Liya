create table if not exists public.liya_ai_consents (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  consent_version text not null,
  granted boolean not null default false,
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.liya_ai_consents enable row level security;
revoke all on public.liya_ai_consents from public, anon, authenticated;
grant select on public.liya_ai_consents to authenticated;
grant all on public.liya_ai_consents to service_role;
drop policy if exists liya_ai_consent_owner_read on public.liya_ai_consents;
create policy liya_ai_consent_owner_read on public.liya_ai_consents for select to authenticated
  using (owner_id = (select auth.uid()));

create or replace function public.liya_ai_set_consent(p_granted boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare who uuid := auth.uid();
begin
  if who is null or p_granted is null then raise exception 'authentication required'; end if;
  insert into public.liya_ai_consents(owner_id, consent_version, granted, updated_at)
  values (who, 'groq-v1', p_granted, clock_timestamp())
  on conflict (owner_id) do update set consent_version = excluded.consent_version,
    granted = excluded.granted, updated_at = excluded.updated_at;
  return p_granted;
end $$;
revoke all on function public.liya_ai_set_consent(boolean) from public, anon;
grant execute on function public.liya_ai_set_consent(boolean) to authenticated;
