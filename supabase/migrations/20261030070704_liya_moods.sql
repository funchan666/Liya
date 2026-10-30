-- A calendar day is supplied by the user's local calendar, rather than inferred
-- from the server's time zone. Pending and saved entries can coexist.
create table public.liya_moods (
    owner_id uuid not null references auth.users(id) on delete cascade,
    day date not null,
    state text not null check (state in ('pending', 'saved')),
    mood text not null,
    note text not null default '',
    updated_at timestamptz not null default now(),
    primary key (owner_id, day, state)
);

alter table public.liya_moods enable row level security;
revoke all on public.liya_moods from anon, authenticated;
grant select, insert, update, delete on public.liya_moods to authenticated;
create policy liya_moods_read_own on public.liya_moods
    for select to authenticated using (owner_id = (select auth.uid()));
create policy liya_moods_insert_own on public.liya_moods
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy liya_moods_update_own on public.liya_moods
    for update to authenticated using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));
create policy liya_moods_delete_own on public.liya_moods
    for delete to authenticated using (owner_id = (select auth.uid()));
