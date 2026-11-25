-- Likes are private to their author. Expose only a total for a catalog item.
create function liya_social_private.media_like_total(p_media_id text)
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) from public.liya_media_likes
  where media_id = p_media_id and (select auth.uid()) is not null
    and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false';
$$;
revoke all on function liya_social_private.media_like_total(text) from public, anon, authenticated;
grant execute on function liya_social_private.media_like_total(text) to authenticated;

-- Count the same comment rows the caller can open, including their own rows.
create function public.liya_media_engagement(p_media_ids text[])
returns table(media_id text, like_count bigint, comment_count bigint)
language sql stable security invoker set search_path = '' as $$
  select m.id, liya_social_private.media_like_total(m.id),
         (select count(*) from public.liya_video_comments c where c.media_id = m.id)
    from public.liya_example_media m
   where (select auth.uid()) is not null
     and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
     and m.kind in ('photo', 'video') and m.id = any(p_media_ids);
$$;
revoke all on function public.liya_media_engagement(text[]) from public, anon, authenticated;
grant execute on function public.liya_media_engagement(text[]) to authenticated;

-- A report must point at a visible comment on that specific photo or video.
-- Keep the original video-only starter keys supported by existing clients.
alter policy video_comment_reports_insert on public.liya_video_comment_reports
  with check (
    reporter_id = (select auth.uid())
    and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
    and exists (
      select 1 from public.liya_example_media m
      where m.id = liya_video_comment_reports.media_id and (
        (m.kind in ('photo','video') and comment_id is not null and preset_key is null and exists (
          select 1 from public.liya_video_comments c
          where c.id = liya_video_comment_reports.comment_id and c.media_id = m.id
            and c.owner_id <> (select auth.uid()) and c.body = liya_video_comment_reports.body_snapshot
        )) or (m.kind = 'video' and comment_id is null and preset_key in (m.id || ':starter:0', m.id || ':starter:1'))
      )
    )
  );
