-- Staged migration: new community submissions are held for human review.
-- Existing content has no review row and remains visible. No existing content is deleted.
create table liya_social_private.moderation_content (
  kind text not null check (kind in ('profile', 'post', 'post_comment', 'media_comment')),
  content_id uuid not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  revision bigint not null default 1 check (revision > 0),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  primary key (kind, content_id)
);
create index liya_moderation_content_pending on liya_social_private.moderation_content(submitted_at, kind, content_id) where status = 'pending';
create index liya_moderation_content_owner on liya_social_private.moderation_content(owner_id, kind, content_id);
alter table liya_social_private.moderation_content enable row level security;
revoke all on liya_social_private.moderation_content from public, anon, authenticated;

-- Queue entries contain identifiers only; source reports retain their existing RLS and deletion rules.
create table liya_social_private.moderation_reports (
  kind text not null check (kind in ('social', 'curated', 'media_comment', 'post_comment', 'message')),
  report_id uuid not null,
  status text not null default 'pending' check (status in ('pending', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  primary key (kind, report_id)
);
create index liya_moderation_reports_pending on liya_social_private.moderation_reports(created_at, kind, report_id) where status = 'pending';
alter table liya_social_private.moderation_reports enable row level security;
revoke all on liya_social_private.moderation_reports from public, anon, authenticated;

-- Keep unapproved public profile fields private while retaining the last approved profile.
create table liya_social_private.moderation_profiles (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  signature text not null check (char_length(signature) <= 500),
  avatar_path text check (avatar_path is null or avatar_path like owner_id::text || '/avatars/%'),
  submission_txid bigint not null
);
alter table liya_social_private.moderation_profiles enable row level security;
revoke all on liya_social_private.moderation_profiles from public, anon, authenticated;

create table liya_social_private.hidden_profiles (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  hidden_at timestamptz not null default now()
);
alter table liya_social_private.hidden_profiles enable row level security;
revoke all on liya_social_private.hidden_profiles from public, anon, authenticated;

-- Keep catalog rows and their stable sort positions while denying new object access.
create table liya_social_private.hidden_curated_media (
  media_id text primary key references public.liya_example_media(id) on delete cascade,
  hidden_at timestamptz not null default now()
);
alter table liya_social_private.hidden_curated_media enable row level security;
revoke all on liya_social_private.hidden_curated_media from public, anon, authenticated;

create table liya_social_private.hidden_curated_starters (
  media_id text not null references public.liya_example_media(id) on delete cascade,
  position integer not null check (position in (0, 1)),
  hidden_at timestamptz not null default now(),
  primary key (media_id, position)
);
alter table liya_social_private.hidden_curated_starters enable row level security;
revoke all on liya_social_private.hidden_curated_starters from public, anon, authenticated;

-- New clients fail closed if this lookup is unavailable; only positions are returned.
create function public.liya_hidden_curated_starters(p_media_id text)
returns table("position" integer) language sql stable security definer set search_path = '' as $$
  select h.position from liya_social_private.hidden_curated_starters h
  where (select auth.uid()) is not null and h.media_id = p_media_id;
$$;
revoke all on function public.liya_hidden_curated_starters(text) from public, anon, authenticated;
grant execute on function public.liya_hidden_curated_starters(text) to authenticated;

create function liya_social_private.curated_object_visible(p_object_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and not exists (
    select 1 from public.liya_example_media m
    join liya_social_private.hidden_curated_media h on h.media_id = m.id
    where m.object_key = p_object_key
  );
$$;
revoke all on function liya_social_private.curated_object_visible(text) from public, anon, authenticated;
grant execute on function liya_social_private.curated_object_visible(text) to authenticated;
create policy liya_moderation_curated_objects_read on storage.objects as restrictive for select to authenticated
  using (bucket_id <> 'liya-example-media' or liya_social_private.curated_object_visible(name));

create function liya_social_private.profile_visible(p_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and not exists (select 1 from liya_social_private.hidden_profiles h where h.owner_id = p_id);
$$;
revoke all on function liya_social_private.profile_visible(uuid) from public, anon, authenticated;
grant execute on function liya_social_private.profile_visible(uuid) to authenticated;
create policy liya_moderation_people_read on public.liya_people as restrictive for select to authenticated
  using (id = (select auth.uid()) or liya_social_private.profile_visible(id));

create function liya_social_private.stage_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Trusted server-side administrative changes are applied directly.
  if (select auth.uid()) is null then return new; end if;
  if new.id <> (select auth.uid()) then raise exception 'invalid profile owner'; end if;
  -- An INSERT ... ON CONFLICT UPDATE sees the sanitized INSERT as EXCLUDED.
  -- Preserve the submission already recorded by this same transaction.
  if tg_op = 'UPDATE' and new.display_name = 'Liya member' and new.signature = '' and new.avatar_path is null
     and exists (select 1 from liya_social_private.moderation_profiles p where p.owner_id = new.id and p.submission_txid = txid_current()) then
    new := old;
    if exists (select 1 from liya_social_private.moderation_profiles p where p.owner_id = new.id and p.submission_txid = txid_current() and p.avatar_path is null) then
      new.avatar_path := null;
    end if;
    return new;
  end if;
  insert into liya_social_private.moderation_profiles(owner_id, display_name, signature, avatar_path, submission_txid)
    values(new.id, new.display_name, new.signature, new.avatar_path, txid_current())
    on conflict(owner_id) do update set display_name = excluded.display_name,
      signature = excluded.signature, avatar_path = excluded.avatar_path, submission_txid = excluded.submission_txid;
  insert into liya_social_private.moderation_content(kind, content_id, owner_id)
    values('profile', new.id, new.id)
    on conflict(kind, content_id) do update set status = 'pending', revision = liya_social_private.moderation_content.revision + 1,
      submitted_at = now(), reviewed_at = null;
  if tg_op = 'INSERT' then
    new.display_name := 'Liya member'; new.signature := ''; new.avatar_path := null;
  else
    new.display_name := old.display_name; new.signature := old.signature;
    if new.avatar_path is not null then new.avatar_path := old.avatar_path; end if;
  end if;
  return new;
end;
$$;
revoke all on function liya_social_private.stage_profile() from public, anon, authenticated;
create trigger liya_stage_profile before insert or update on public.liya_people for each row execute function liya_social_private.stage_profile();

create function liya_social_private.remove_profile_submission() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from liya_social_private.moderation_profiles where owner_id = old.id;
  delete from liya_social_private.hidden_profiles where owner_id = old.id;
  delete from liya_social_private.moderation_content where kind = 'profile' and content_id = old.id;
  return old;
end;
$$;
revoke all on function liya_social_private.remove_profile_submission() from public, anon, authenticated;
create trigger liya_remove_profile_submission after delete on public.liya_people for each row execute function liya_social_private.remove_profile_submission();

create function public.liya_my_profile_submission()
returns table(display_name text, signature text, avatar_path text)
language sql stable security definer set search_path = '' as $$
  select p.display_name, p.signature, p.avatar_path from liya_social_private.moderation_profiles p
    join liya_social_private.moderation_content m on m.kind = 'profile' and m.content_id = p.owner_id
  where (select auth.uid()) is not null and p.owner_id = (select auth.uid()) and m.status in ('pending', 'rejected');
$$;
revoke all on function public.liya_my_profile_submission() from public, anon, authenticated;
grant execute on function public.liya_my_profile_submission() to authenticated;

create function liya_social_private.moderation_visible(p_kind text, p_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and not exists (
    select 1 from liya_social_private.moderation_content m
    where m.kind = p_kind and m.content_id = p_id and m.status <> 'approved'
  );
$$;
revoke all on function liya_social_private.moderation_visible(text, uuid) from public, anon, authenticated;
grant execute on function liya_social_private.moderation_visible(text, uuid) to authenticated;

create function liya_social_private.queue_content() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_kind text;
begin
  v_kind := case tg_table_name when 'liya_posts' then 'post' when 'liya_post_comments' then 'post_comment' when 'liya_video_comments' then 'media_comment' end;
  if tg_op = 'DELETE' then
    delete from liya_social_private.moderation_content where kind = v_kind and content_id = old.id;
    return old;
  end if;
  if tg_op = 'UPDATE' and tg_table_name = 'liya_posts' then
    if new.id is distinct from old.id then
      delete from liya_social_private.moderation_content where kind = v_kind and content_id = old.id;
    end if;
    if new.id is not distinct from old.id and new.body is not distinct from old.body and new.tags is not distinct from old.tags
       and new.media_paths is not distinct from old.media_paths and new.media_kinds is not distinct from old.media_kinds then
      return new;
    end if;
  end if;
  insert into liya_social_private.moderation_content(kind, content_id, owner_id)
  values(v_kind, new.id, new.owner_id)
  on conflict(kind, content_id) do update set status = 'pending', revision = liya_social_private.moderation_content.revision + 1,
    submitted_at = now(), reviewed_at = null, owner_id = excluded.owner_id;
  return new;
end;
$$;
revoke all on function liya_social_private.queue_content() from public, anon, authenticated;
create trigger liya_moderate_posts after insert or update or delete on public.liya_posts for each row execute function liya_social_private.queue_content();
create trigger liya_moderate_post_comments after insert or delete on public.liya_post_comments for each row execute function liya_social_private.queue_content();
create trigger liya_moderate_media_comments after insert or delete on public.liya_video_comments for each row execute function liya_social_private.queue_content();

-- A pending comment should not create a notification for a comment the recipient cannot see.
drop trigger liya_notify_comment on public.liya_post_comments;

-- Restrictive policies combine with existing ownership/blocking policies rather than replacing them.
create policy liya_moderation_posts_read on public.liya_posts as restrictive for select to authenticated
using (owner_id = (select auth.uid()) or liya_social_private.moderation_visible('post', id));
create policy liya_moderation_post_comments_read on public.liya_post_comments as restrictive for select to authenticated
using (owner_id = (select auth.uid()) or liya_social_private.moderation_visible('post_comment', id));
create policy liya_moderation_media_comments_read on public.liya_video_comments as restrictive for select to authenticated
using (owner_id = (select auth.uid()) or liya_social_private.moderation_visible('media_comment', id));

-- Photo counts use a security-definer helper; apply the same visibility check explicitly.
create or replace function liya_social_private.photo_counts(p_media_id text)
returns table(like_count bigint, comment_count bigint)
language sql stable security definer set search_path = '' as $$
  select
    (select count(*) from public.liya_media_likes l where l.media_id = p_media_id),
    (select count(*) from public.liya_video_comments c
      where c.media_id = p_media_id
        and (c.owner_id = (select auth.uid()) or (not liya_social_private.blocked(c.owner_id)
          and liya_social_private.moderation_visible('media_comment', c.id))))
  where (select auth.uid()) is not null
    and exists (select 1 from public.liya_example_media m where m.id = p_media_id and m.kind = 'photo');
$$;
revoke all on function liya_social_private.photo_counts(text) from public, anon;
grant execute on function liya_social_private.photo_counts(text) to authenticated;

-- Report community comments with a verified snapshot and preserve original report behavior.
create table public.liya_post_comment_reports (
  id uuid primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  comment_id uuid not null,
  post_id uuid not null,
  target_user uuid not null references auth.users(id) on delete cascade,
  body_snapshot text not null check (char_length(trim(body_snapshot)) between 1 and 2000),
  reason text not null check (reason in ('Sexual content','Harassment','Discrimination','Incorrect content','Other')),
  created_at timestamptz not null default now(),
  check (reporter_id <> target_user)
);
create index liya_post_comment_reports_reporter on public.liya_post_comment_reports(reporter_id, created_at);
create index liya_post_comment_reports_target on public.liya_post_comment_reports(target_user);
alter table public.liya_post_comment_reports enable row level security;
revoke all on public.liya_post_comment_reports from public, anon, authenticated;
grant select on public.liya_post_comment_reports to authenticated;
grant insert(id, reporter_id, comment_id, post_id, target_user, body_snapshot, reason) on public.liya_post_comment_reports to authenticated;
create policy post_comment_reports_read on public.liya_post_comment_reports for select to authenticated using (reporter_id = (select auth.uid()));
create policy post_comment_reports_insert on public.liya_post_comment_reports for insert to authenticated with check (
  reporter_id = (select auth.uid()) and exists (
    select 1 from public.liya_post_comments c where c.id = comment_id and c.post_id = liya_post_comment_reports.post_id
      and c.owner_id = target_user and c.owner_id <> (select auth.uid()) and c.body = body_snapshot
  )
);

-- Only the recipient may report a private message; no unreported conversation is copied.
create table public.liya_message_reports (
  id uuid primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null,
  target_user uuid not null references auth.users(id) on delete cascade,
  body_snapshot text not null check (char_length(body_snapshot) <= 4000),
  media_paths text[] not null default '{}',
  media_kinds text[] not null default '{}',
  reason text not null check (reason in ('Sexual content','Harassment','Discrimination','Incorrect content','Other')),
  created_at timestamptz not null default now(),
  check (reporter_id <> target_user),
  check (cardinality(media_paths) = cardinality(media_kinds)),
  check (char_length(trim(body_snapshot)) > 0 or cardinality(media_paths) > 0)
);
create index liya_message_reports_reporter on public.liya_message_reports(reporter_id, created_at);
create index liya_message_reports_target on public.liya_message_reports(target_user);
alter table public.liya_message_reports enable row level security;
revoke all on public.liya_message_reports from public, anon, authenticated;
grant select on public.liya_message_reports to authenticated;
grant insert(id, reporter_id, message_id, target_user, body_snapshot, media_paths, media_kinds, reason) on public.liya_message_reports to authenticated;
create policy message_reports_read on public.liya_message_reports for select to authenticated using (reporter_id = (select auth.uid()));
create policy message_reports_insert on public.liya_message_reports for insert to authenticated with check (
  reporter_id = (select auth.uid()) and exists (
    select 1 from public.liya_messages m where m.id = liya_message_reports.message_id
      and m.recipient_id = (select auth.uid()) and m.sender_id = liya_message_reports.target_user
      and m.body = liya_message_reports.body_snapshot and m.media_paths = liya_message_reports.media_paths
      and m.media_kinds = liya_message_reports.media_kinds
  )
);

-- The shared comments table also accepts photo comments; their reports must be accepted too.
drop policy video_comment_reports_insert on public.liya_video_comment_reports;
create policy video_comment_reports_insert on public.liya_video_comment_reports for insert to authenticated with check (
 reporter_id = (select auth.uid()) and exists (
   select 1 from public.liya_example_media m where m.id = liya_video_comment_reports.media_id and m.kind in ('video', 'photo')
 ) and (
   (comment_id is null and preset_key in (liya_video_comment_reports.media_id || ':starter:0', liya_video_comment_reports.media_id || ':starter:1')) or
   (comment_id is not null and exists (select 1 from public.liya_video_comments c
     where c.id = liya_video_comment_reports.comment_id and c.media_id = liya_video_comment_reports.media_id
       and c.owner_id <> (select auth.uid()) and c.body = liya_video_comment_reports.body_snapshot))
 )
);

create function liya_social_private.queue_report() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_kind text;
begin
  v_kind := case tg_table_name when 'liya_social_reports' then 'social' when 'liya_content_reports' then 'curated'
    when 'liya_video_comment_reports' then 'media_comment' when 'liya_post_comment_reports' then 'post_comment'
    when 'liya_message_reports' then 'message' end;
  if tg_op = 'DELETE' then
    delete from liya_social_private.moderation_reports where kind = v_kind and report_id = old.id;
    return old;
  end if;
  insert into liya_social_private.moderation_reports(kind, report_id, created_at) values(v_kind, new.id, new.created_at)
    on conflict(kind, report_id) do nothing;
  return new;
end;
$$;
revoke all on function liya_social_private.queue_report() from public, anon, authenticated;
create function liya_social_private.report_timestamp() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.created_at := now();
  return new;
end;
$$;
revoke all on function liya_social_private.report_timestamp() from public, anon, authenticated;
create trigger liya_time_social_reports before insert on public.liya_social_reports for each row execute function liya_social_private.report_timestamp();
create trigger liya_time_content_reports before insert on public.liya_content_reports for each row execute function liya_social_private.report_timestamp();
create trigger liya_time_media_comment_reports before insert on public.liya_video_comment_reports for each row execute function liya_social_private.report_timestamp();
create trigger liya_time_post_comment_reports before insert on public.liya_post_comment_reports for each row execute function liya_social_private.report_timestamp();
create trigger liya_time_message_reports before insert on public.liya_message_reports for each row execute function liya_social_private.report_timestamp();
create trigger liya_queue_social_reports after insert or delete on public.liya_social_reports for each row execute function liya_social_private.queue_report();
create trigger liya_queue_content_reports after insert or delete on public.liya_content_reports for each row execute function liya_social_private.queue_report();
create trigger liya_queue_media_comment_reports after insert or delete on public.liya_video_comment_reports for each row execute function liya_social_private.queue_report();
create trigger liya_queue_post_comment_reports after insert or delete on public.liya_post_comment_reports for each row execute function liya_social_private.queue_report();
create trigger liya_queue_message_reports after insert or delete on public.liya_message_reports for each row execute function liya_social_private.queue_report();
insert into liya_social_private.moderation_reports(kind,report_id,created_at) select 'social',id,created_at from public.liya_social_reports on conflict do nothing;
insert into liya_social_private.moderation_reports(kind,report_id,created_at) select 'curated',id,created_at from public.liya_content_reports on conflict do nothing;
insert into liya_social_private.moderation_reports(kind,report_id,created_at) select 'media_comment',id,created_at from public.liya_video_comment_reports on conflict do nothing;

-- Authors can see only their own moderation states; no content or other users' reports are exposed.
create function public.liya_my_moderation_status()
returns table(kind text, content_id uuid, status text)
language sql stable security definer set search_path = '' as $$
  select m.kind, m.content_id,
    case when m.kind = 'profile' and exists (select 1 from liya_social_private.hidden_profiles h where h.owner_id = m.owner_id)
      then 'hidden' else m.status end
  from liya_social_private.moderation_content m
  where (select auth.uid()) is not null and m.owner_id = (select auth.uid());
$$;
revoke all on function public.liya_my_moderation_status() from public, anon, authenticated;
grant execute on function public.liya_my_moderation_status() to authenticated;

-- Reporters can read only their own report state and reason, never another user's reports.
create function public.liya_my_report_status()
returns table(kind text, report_id uuid, status text, reason text, created_at timestamptz, resolved_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select q.kind, q.report_id, q.status, r.reason, q.created_at, q.resolved_at
    from liya_social_private.moderation_reports q join public.liya_social_reports r on q.kind = 'social' and r.id = q.report_id
    where (select auth.uid()) is not null and r.reporter_id = (select auth.uid())
  union all
  select q.kind, q.report_id, q.status, r.reason, q.created_at, q.resolved_at
    from liya_social_private.moderation_reports q join public.liya_content_reports r on q.kind = 'curated' and r.id = q.report_id
    where (select auth.uid()) is not null and r.reporter_id = (select auth.uid())
  union all
  select q.kind, q.report_id, q.status, r.reason, q.created_at, q.resolved_at
    from liya_social_private.moderation_reports q join public.liya_video_comment_reports r on q.kind = 'media_comment' and r.id = q.report_id
    where (select auth.uid()) is not null and r.reporter_id = (select auth.uid())
  union all
  select q.kind, q.report_id, q.status, r.reason, q.created_at, q.resolved_at
    from liya_social_private.moderation_reports q join public.liya_post_comment_reports r on q.kind = 'post_comment' and r.id = q.report_id
    where (select auth.uid()) is not null and r.reporter_id = (select auth.uid())
  union all
  select q.kind, q.report_id, q.status, r.reason, q.created_at, q.resolved_at
    from liya_social_private.moderation_reports q join public.liya_message_reports r on q.kind = 'message' and r.id = q.report_id
    where (select auth.uid()) is not null and r.reporter_id = (select auth.uid());
$$;
revoke all on function public.liya_my_report_status() from public, anon, authenticated;
grant execute on function public.liya_my_report_status() to authenticated;

-- Private audit trail is removed with the corresponding content or report queue row.
create table liya_social_private.moderation_events (
 id bigint generated always as identity primary key,
 category text not null check (category in ('content', 'report')),
 kind text not null, subject_id uuid not null,
 decision text not null, actor text not null check (char_length(trim(actor)) between 1 and 120),
 created_at timestamptz not null default now()
);
create index liya_moderation_events_subject on liya_social_private.moderation_events(category, kind, subject_id);
alter table liya_social_private.moderation_events enable row level security;
revoke all on liya_social_private.moderation_events from public, anon, authenticated;
create function liya_social_private.clear_moderation_events() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'moderation_content' then
    delete from liya_social_private.moderation_events where category = 'content' and kind = old.kind and subject_id = old.content_id;
  else
    delete from liya_social_private.moderation_events where category = 'report' and kind = old.kind and subject_id = old.report_id;
  end if;
  return old;
end;
$$;
revoke all on function liya_social_private.clear_moderation_events() from public, anon, authenticated;
create trigger liya_clear_content_events after delete on liya_social_private.moderation_content for each row execute function liya_social_private.clear_moderation_events();
create trigger liya_clear_report_events after delete on liya_social_private.moderation_reports for each row execute function liya_social_private.clear_moderation_events();

-- All reviewer actions remain restricted to a trusted database operator.
create function liya_social_private.review_content(p_kind text, p_id uuid, p_revision bigint, p_decision text, p_actor text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare changed integer; old_status text; v_author uuid; v_recipient uuid; v_post uuid;
begin
  if p_decision not in ('approved', 'rejected') or char_length(trim(coalesce(p_actor, ''))) not between 1 and 120 then raise exception 'invalid review'; end if;
  if p_kind = 'profile' then
    if (select auth.uid()) is not null then raise exception 'trusted database session required'; end if;
    perform 1 from public.liya_people where id = p_id for update;
  end if;
  select status into old_status from liya_social_private.moderation_content
    where kind = p_kind and content_id = p_id and revision = p_revision for update;
  update liya_social_private.moderation_content set status = p_decision, reviewed_at = now()
    where kind = p_kind and content_id = p_id and revision = p_revision
      and (status = 'pending' or (status = 'rejected' and p_decision = 'approved'));
  get diagnostics changed = row_count;
  if changed = 1 then
    insert into liya_social_private.moderation_events(category, kind, subject_id, decision, actor) values('content', p_kind, p_id, p_decision, trim(p_actor));
    if p_kind = 'profile' and p_decision = 'approved' then
      update public.liya_people p set display_name = s.display_name, signature = s.signature, avatar_path = s.avatar_path
        from liya_social_private.moderation_profiles s where s.owner_id = p_id and p.id = s.owner_id;
      if not found then raise exception 'profile submission unavailable'; end if;
      delete from liya_social_private.moderation_profiles where owner_id = p_id;
    end if;
    if p_kind = 'post_comment' and old_status = 'pending' and p_decision = 'approved' then
      select c.owner_id, p.owner_id, p.id into v_author, v_recipient, v_post
        from public.liya_post_comments c join public.liya_posts p on p.id = c.post_id where c.id = p_id;
      if v_recipient is not null and v_author <> v_recipient
         and not exists (select 1 from public.liya_blocks b where (b.owner_id = v_recipient and b.target_id = v_author) or (b.owner_id = v_author and b.target_id = v_recipient))
         and not exists (select 1 from liya_social_private.moderation_content m where m.kind = 'post' and m.content_id = v_post and m.status <> 'approved') then
        insert into public.liya_social_notifications(owner_id, actor_id, kind, post_id) values(v_recipient, v_author, 'comment', v_post);
      end if;
    end if;
    update public.liya_feed_revision set revision = revision + 1 where id = true;
  end if;
  return changed = 1;
end;
$$;
revoke all on function liya_social_private.review_content(text, uuid, bigint, text, text) from public, anon, authenticated;
create function liya_social_private.review_report(p_kind text, p_id uuid, p_decision text, p_actor text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if p_decision not in ('resolved', 'dismissed') or char_length(trim(coalesce(p_actor, ''))) not between 1 and 120 then raise exception 'invalid review'; end if;
  update liya_social_private.moderation_reports set status = p_decision, resolved_at = now()
    where kind = p_kind and report_id = p_id and status = 'pending';
  get diagnostics changed = row_count;
  if changed = 1 then
    insert into liya_social_private.moderation_events(category, kind, subject_id, decision, actor) values('report', p_kind, p_id, p_decision, trim(p_actor));
    update public.liya_feed_revision set revision = revision + 1 where id = true;
  end if;
  return changed = 1;
end;
$$;
revoke all on function liya_social_private.review_report(text, uuid, text, text) from public, anon, authenticated;

-- Hide existing or approved content without deleting it; edits re-enter the queue.
create function liya_social_private.hide_content(p_kind text, p_id uuid, p_actor text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
  if char_length(trim(coalesce(p_actor, ''))) not between 1 and 120 then raise exception 'invalid reviewer'; end if;
  if p_kind = 'post' then select owner_id into v_owner from public.liya_posts where id = p_id for update;
  elsif p_kind = 'post_comment' then select owner_id into v_owner from public.liya_post_comments where id = p_id for update;
  elsif p_kind = 'media_comment' then select owner_id into v_owner from public.liya_video_comments where id = p_id for update;
  else raise exception 'invalid content type'; end if;
  if v_owner is null then return false; end if;
  insert into liya_social_private.moderation_content(kind, content_id, owner_id, status, reviewed_at)
    values(p_kind, p_id, v_owner, 'rejected', now())
    on conflict(kind, content_id) do update set status = 'rejected', revision = liya_social_private.moderation_content.revision + 1, reviewed_at = now();
  insert into liya_social_private.moderation_events(category, kind, subject_id, decision, actor) values('content', p_kind, p_id, 'rejected', trim(p_actor));
  update public.liya_feed_revision set revision = revision + 1 where id = true;
  return true;
end;
$$;
revoke all on function liya_social_private.hide_content(text, uuid, text) from public, anon, authenticated;

-- Hide or restore a reported public profile without deleting its fields or relationships.
create function liya_social_private.set_profile_hidden(p_owner uuid, p_hidden boolean, p_actor text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if (select auth.uid()) is not null or p_hidden is null or char_length(trim(coalesce(p_actor, ''))) not between 1 and 120 then
    raise exception 'trusted database session and reviewer required';
  end if;
  perform 1 from public.liya_people where id = p_owner for update;
  if not found then return false; end if;
  if p_hidden then
    insert into liya_social_private.hidden_profiles(owner_id) values(p_owner) on conflict do nothing;
  else
    delete from liya_social_private.hidden_profiles where owner_id = p_owner;
  end if;
  get diagnostics changed = row_count;
  if changed = 1 then
    insert into liya_social_private.moderation_content(kind, content_id, owner_id, status, reviewed_at)
      values('profile', p_owner, p_owner, 'approved', now()) on conflict(kind, content_id) do nothing;
    insert into liya_social_private.moderation_events(category, kind, subject_id, decision, actor)
      values('content', 'profile', p_owner, case when p_hidden then 'hidden' else 'restored' end, trim(p_actor));
    update public.liya_feed_revision set revision = revision + 1 where id = true;
  end if;
  return true;
end;
$$;
revoke all on function liya_social_private.set_profile_hidden(uuid, boolean, text) from public, anon, authenticated;

-- Curated IDs are text, so retain their review history in a separate private table.
create table liya_social_private.curated_moderation_events (
  id bigint generated always as identity primary key,
  media_id text not null references public.liya_example_media(id) on delete cascade,
  decision text not null check (decision in ('hidden', 'restored')),
  actor text not null check (char_length(trim(actor)) between 1 and 120),
  created_at timestamptz not null default now()
);
alter table liya_social_private.curated_moderation_events enable row level security;
revoke all on liya_social_private.curated_moderation_events from public, anon, authenticated;

create function liya_social_private.set_curated_hidden(p_media_id text, p_hidden boolean, p_actor text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if (select auth.uid()) is not null or p_hidden is null or char_length(trim(coalesce(p_actor, ''))) not between 1 and 120 then
    raise exception 'trusted database session and reviewer required';
  end if;
  perform 1 from public.liya_example_media where id = p_media_id for update;
  if not found then return false; end if;
  if p_hidden then
    insert into liya_social_private.hidden_curated_media(media_id) values(p_media_id) on conflict do nothing;
  else
    delete from liya_social_private.hidden_curated_media where media_id = p_media_id;
  end if;
  get diagnostics changed = row_count;
  if changed = 1 then
    insert into liya_social_private.curated_moderation_events(media_id, decision, actor)
      values(p_media_id, case when p_hidden then 'hidden' else 'restored' end, trim(p_actor));
    update public.liya_feed_revision set revision = revision + 1 where id = true;
  end if;
  return true;
end;
$$;
revoke all on function liya_social_private.set_curated_hidden(text, boolean, text) from public, anon, authenticated;

create table liya_social_private.curated_starter_events (
  id bigint generated always as identity primary key,
  media_id text not null references public.liya_example_media(id) on delete cascade,
  position integer not null check (position in (0, 1)),
  decision text not null check (decision in ('hidden', 'restored')),
  actor text not null check (char_length(trim(actor)) between 1 and 120),
  created_at timestamptz not null default now()
);
alter table liya_social_private.curated_starter_events enable row level security;
revoke all on liya_social_private.curated_starter_events from public, anon, authenticated;

create function liya_social_private.set_curated_starter_hidden(p_media_id text, p_position integer, p_hidden boolean, p_actor text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if (select auth.uid()) is not null or p_hidden is null or p_position is null or p_position not in (0, 1)
     or char_length(trim(coalesce(p_actor, ''))) not between 1 and 120 then
    raise exception 'trusted database session and reviewer required';
  end if;
  perform 1 from public.liya_example_media where id = p_media_id and kind = 'video' for update;
  if not found then return false; end if;
  if p_hidden then
    insert into liya_social_private.hidden_curated_starters(media_id, position) values(p_media_id, p_position) on conflict do nothing;
  else
    delete from liya_social_private.hidden_curated_starters where media_id = p_media_id and position = p_position;
  end if;
  get diagnostics changed = row_count;
  if changed = 1 then
    insert into liya_social_private.curated_starter_events(media_id, position, decision, actor)
      values(p_media_id, p_position, case when p_hidden then 'hidden' else 'restored' end, trim(p_actor));
    update public.liya_feed_revision set revision = revision + 1 where id = true;
  end if;
  return true;
end;
$$;
revoke all on function liya_social_private.set_curated_starter_hidden(text, integer, boolean, text) from public, anon, authenticated;
