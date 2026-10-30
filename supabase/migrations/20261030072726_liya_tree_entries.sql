create table public.liya_tree_entries (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  mood text not null check (mood in ('mood-happy','mood-calm','mood-upset','mood-blue','mood-teal')),
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
alter table public.liya_tree_entries enable row level security;
revoke all on public.liya_tree_entries from public, anon, authenticated;
grant select, insert, delete on public.liya_tree_entries to authenticated;
create policy liya_tree_read_own on public.liya_tree_entries for select to authenticated using (owner_id = (select auth.uid()));
create policy liya_tree_insert_own on public.liya_tree_entries for insert to authenticated with check (owner_id = (select auth.uid()));
create policy liya_tree_delete_own on public.liya_tree_entries for delete to authenticated using (owner_id = (select auth.uid()));
