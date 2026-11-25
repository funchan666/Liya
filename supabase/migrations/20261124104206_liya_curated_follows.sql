-- Keep explicit unfollows so importing an older installation cannot undo them.
create table public.liya_curated_follows (
  owner_id uuid not null references auth.users(id) on delete cascade,
  media_id text not null references public.liya_example_media(id) on delete cascade,
  is_following boolean not null,
  primary key (owner_id, media_id)
);
create index liya_curated_follows_media_id_idx on public.liya_curated_follows(media_id);
alter table public.liya_curated_follows enable row level security;
revoke all on public.liya_curated_follows from public, anon, authenticated;
grant select, insert, update on public.liya_curated_follows to authenticated;

create policy curated_follows_owner on public.liya_curated_follows
  for all to authenticated
  using (
    owner_id = (select auth.uid())
    and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
  )
  with check (
    owner_id = (select auth.uid())
    and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
    and exists (select 1 from public.liya_example_media m
                where m.id = liya_curated_follows.media_id and m.kind = 'photo')
  );
