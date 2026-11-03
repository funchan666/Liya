-- Shared comments on curated videos. Preset comments remain clearly identified in the app.
create table public.liya_video_comments (
  id uuid primary key,
  media_id text not null references public.liya_example_media(id) on delete cascade,
  owner_id uuid not null references public.liya_people(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index liya_video_comments_media on public.liya_video_comments(media_id, created_at, id);
create index liya_video_comments_owner on public.liya_video_comments(owner_id);
alter table public.liya_video_comments enable row level security;
revoke all on public.liya_video_comments from public, anon, authenticated;
grant select, insert, delete on public.liya_video_comments to authenticated;
create policy video_comments_read on public.liya_video_comments for select to authenticated
  using (owner_id = (select auth.uid()) or not liya_social_private.blocked(owner_id));
create policy video_comments_insert on public.liya_video_comments for insert to authenticated
  with check (owner_id = (select auth.uid()) and exists (
    select 1 from public.liya_example_media m where m.id = liya_video_comments.media_id and m.kind = 'video'
  ));
create policy video_comments_delete on public.liya_video_comments for delete to authenticated
  using (owner_id = (select auth.uid()));
create trigger liya_sync_video_comments after insert or delete on public.liya_video_comments
  for each statement execute function liya_social_private.signal_feed();

-- Reports retain a snapshot even if the original comment is later removed.
create table public.liya_video_comment_reports (
  id uuid primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  media_id text not null references public.liya_example_media(id),
  comment_id uuid,
  preset_key text,
  body_snapshot text not null check (char_length(trim(body_snapshot)) between 1 and 2000),
  reason text not null check (reason in ('Sexual content','Harassment','Discrimination','Incorrect content','Other')),
  created_at timestamptz not null default now(),
  check ((comment_id is not null and preset_key is null) or (comment_id is null and preset_key is not null)),
  check (preset_key is null or char_length(preset_key) between 1 and 120)
);
create index liya_video_comment_reports_reporter on public.liya_video_comment_reports(reporter_id, created_at);
alter table public.liya_video_comment_reports enable row level security;
revoke all on public.liya_video_comment_reports from public, anon, authenticated;
grant select, insert on public.liya_video_comment_reports to authenticated;
create policy video_comment_reports_read on public.liya_video_comment_reports for select to authenticated
  using (reporter_id = (select auth.uid()));
create policy video_comment_reports_insert on public.liya_video_comment_reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and exists (
    select 1 from public.liya_example_media m where m.id = liya_video_comment_reports.media_id and m.kind = 'video'
  ) and (
    (comment_id is null and preset_key in (liya_video_comment_reports.media_id || ':starter:0', liya_video_comment_reports.media_id || ':starter:1')) or
    (comment_id is not null and exists (
      select 1 from public.liya_video_comments c
      where c.id = liya_video_comment_reports.comment_id and c.media_id = liya_video_comment_reports.media_id
        and c.owner_id <> (select auth.uid()) and c.body = liya_video_comment_reports.body_snapshot
    ))
  ));
