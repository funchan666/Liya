create table public.liya_media_likes (
  owner_id uuid not null references auth.users(id) on delete cascade,
  media_id text not null references public.liya_example_media(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(owner_id, media_id)
);
alter table public.liya_media_likes enable row level security;
revoke all on public.liya_media_likes from public, anon, authenticated;
grant select, insert, delete on public.liya_media_likes to authenticated;
create policy liya_likes_read_own on public.liya_media_likes for select to authenticated using (owner_id = (select auth.uid()));
create policy liya_likes_insert_own on public.liya_media_likes for insert to authenticated with check (owner_id = (select auth.uid()));
create policy liya_likes_delete_own on public.liya_media_likes for delete to authenticated using (owner_id = (select auth.uid()));
