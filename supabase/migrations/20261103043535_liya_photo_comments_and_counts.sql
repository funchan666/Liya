-- Shared comments use the existing curated-media comment table and ownership rules.
drop policy video_comments_insert on public.liya_video_comments;
create policy video_comments_insert on public.liya_video_comments for insert to authenticated
  with check (owner_id = (select auth.uid()) and exists (
    select 1 from public.liya_example_media m
    where m.id = liya_video_comments.media_id and m.kind in ('video', 'photo')
  ));

create index if not exists liya_media_likes_media on public.liya_media_likes(media_id);
create trigger liya_sync_media_likes after insert or delete on public.liya_media_likes
  for each statement execute function liya_social_private.signal_feed();

-- Only aggregate counts leave this private helper; individual likes remain private.
create function liya_social_private.photo_counts(p_media_id text)
returns table(like_count bigint, comment_count bigint)
language sql stable security definer set search_path = '' as $$
  select
    (select count(*) from public.liya_media_likes l where l.media_id = p_media_id),
    (select count(*) from public.liya_video_comments c
      where c.media_id = p_media_id
        and (c.owner_id = (select auth.uid()) or not liya_social_private.blocked(c.owner_id)))
  where (select auth.uid()) is not null
    and exists (select 1 from public.liya_example_media m where m.id = p_media_id and m.kind = 'photo');
$$;
revoke all on function liya_social_private.photo_counts(text) from public, anon;
grant execute on function liya_social_private.photo_counts(text) to authenticated;

create function public.liya_photo_counts(p_media_id text)
returns table(like_count bigint, comment_count bigint)
language sql stable security invoker set search_path = '' as $$
  select * from liya_social_private.photo_counts(p_media_id);
$$;
revoke all on function public.liya_photo_counts(text) from public, anon;
grant execute on function public.liya_photo_counts(text) to authenticated;

-- Community post counts obey the caller's existing post, block and comment policies.
create function public.liya_post_counts(p_post_id uuid)
returns table(like_count bigint, comment_count bigint)
language sql stable security invoker set search_path = '' as $$
  select
    (select count(*) from public.liya_post_likes l where l.post_id = p_post_id),
    (select count(*) from public.liya_post_comments c where c.post_id = p_post_id)
  where exists (select 1 from public.liya_posts p where p.id = p_post_id);
$$;
revoke all on function public.liya_post_counts(uuid) from public, anon;
grant execute on function public.liya_post_counts(uuid) to authenticated;
