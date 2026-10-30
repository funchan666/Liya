-- Private account profile. Additional public social data requires separate policies.
create table public.liya_profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default '' check (char_length(display_name) <= 80),
    signature text not null default '' check (char_length(signature) <= 500),
    tags text[] not null default '{}',
    avatar_path text,
    created_at timestamptz not null default now()
);

alter table public.liya_profiles enable row level security;
revoke all on public.liya_profiles from anon, authenticated;
grant select, insert, update on public.liya_profiles to authenticated;

create policy liya_profiles_read_own on public.liya_profiles
    for select to authenticated using (id = (select auth.uid()));
create policy liya_profiles_insert_own on public.liya_profiles
    for insert to authenticated with check (id = (select auth.uid()));
create policy liya_profiles_update_own on public.liya_profiles
    for update to authenticated using (id = (select auth.uid()))
    with check (id = (select auth.uid()));
