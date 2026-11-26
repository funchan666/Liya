alter table liya_social_private.hidden_curated_starters
  drop constraint hidden_curated_starters_position_check,
  add constraint hidden_curated_starters_position_check check (position >= 0);
alter table liya_social_private.curated_starter_events
  drop constraint curated_starter_events_position_check,
  add constraint curated_starter_events_position_check check (position >= 0);

alter table public.liya_curated_video_prompts add column published_as_comment boolean not null default false;

insert into public.liya_curated_video_prompts as published(video_id, position, display_name, body, published_as_comment)
select edition.media_id, edition.slot, 'Liya Editorial', edition.body, true
from (values
  ('example-photo-001', 0, 'The scarf almost disappears into the trees. The snow caught on it gives the edge away.'),
  ('example-photo-001', 1, 'Some flakes are pinpricks and some are streaks. A still photo with weather moving through it.'),
  ('example-photo-002', 0, 'A whole little landscape fits inside that piece of ice. Look at the cloudy patch near the thumb.'),
  ('example-photo-002', 1, 'That blue coat against the grey shore! The eye lands there before it finds the horizon.'),
  ('example-photo-002', 2, 'Would you have picked that piece up or left it where the water put it?'),
  ('example-photo-003', 0, 'White socks, dark jacket, a very tall wooden door. Everyday details give this street its scale.'),
  ('example-photo-004', 0, 'Follow the buildings up each side. The patch of sky at the top feels tiny.'),
  ('example-photo-004', 1, 'That fingertip takes up almost as much room as a building. Such a playful use of the lens.'),
  ('example-photo-005', 0, 'Three layers in one reflection: hood, jacket and shirt. The orange phone breaks up the greens.'),
  ('example-photo-006', 0, 'The river looks milky green beside those russet trees. It feels like autumn before you notice the leaves.'),
  ('example-photo-006', 1, 'A rock just big enough to perch on. Where would you stop along this bank?'),
  ('example-photo-007', 0, 'The mist softens the line where the mountains meet the water.'),
  ('example-photo-007', 1, 'A small smile on a grey day is the part that sticks with me.'),
  ('example-photo-008', 0, 'The yellow cap and the plaid shirt tied at the waist tell two different color stories.'),
  ('example-photo-009', 0, 'Warm light spills out of the shop while the pavement stays cool. It feels like the moment before heading back outside.'),
  ('example-photo-009', 1, 'The open door gives a glimpse of an entirely different scene behind this portrait.'),
  ('example-photo-010', 0, 'At first it looks like a sunny village street. Then the peaks behind the roofs come into focus.'),
  ('example-photo-010', 1, 'There is a little strip of water tucked under the buildings. Easy to miss on a first look.'),
  ('example-photo-010', 2, 'Bright shades, a blue sky, elbows propped up for a break. This one feels like a good place to linger.'),
  ('example-photo-011', 0, 'A pale strip of sea, a white tee and a dark cap. The whole frame feels as quiet as the horizon.'),
  ('example-photo-013', 0, 'The trail carries on into the fog. Only the next few steps really matter in this frame.'),
  ('example-photo-013', 1, 'Look at the ground beside the path: so many shades of green under that blank sky.'),
  ('example-photo-014', 0, 'That bright stony riverbank leads the eye from the backpack all the way to the bare peaks.'),
  ('example-photo-015', 0, 'The shoulder and the pyramid peak pull your eye in the same direction.'),
  ('example-photo-015', 1, 'The sandy foreground and the clean blue sky do most of the talking here.'),
  ('example-photo-016', 0, 'The mirrored lift has reduced a busy day to a few things: a phone, a bag and a moment alone.'),
  ('example-photo-017', 0, 'Two faces in the gallery, but only the painted one looks straight out at us.'),
  ('example-photo-017', 1, 'The hand beside the cheek makes the portrait and the painting feel like a conversation.'),
  ('example-photo-018', 0, 'The backpack straps and the knit cap suggest a chilly walk. The grin suggests it was worth it.'),
  ('example-photo-019', 0, 'The bouquet is hard to miss. How long did it take you to notice the cats around it?'),
  ('example-photo-019', 1, 'Every cat seems to have its own destination. That makes this sidewalk feel alive.'),
  ('example-photo-019', 2, 'A bunch of white flowers against plain pavement is plenty of color for this frame.'),
  ('example-photo-020', 0, 'Sheep dot the meadow almost up to the mountain. The pasture feels much bigger on a second look.'),
  ('example-photo-020', 1, 'There is such an easy grin in the foreground, while the sheep behind just get on with their day.'),
  ('example-video-001', 0, 'I kept watching the white line where the waves meet the rock.'),
  ('example-video-001', 1, 'My favorite part was the pause before the camera turned.'),
  ('example-video-002', 0, 'The walker gives the cliffs a sense of scale.'),
  ('example-video-002', 1, 'That thin strip of green above the sea caught my eye.'),
  ('example-video-003', 0, 'The spray makes the whole frame feel cool.'),
  ('example-video-003', 1, 'I like the moment when the trees blur into the background.'),
  ('example-video-003', 2, 'One moment you can pick out the trees; the next, the spray draws a curtain across them.'),
  ('example-video-004', 0, 'The lake looked even bluer when the trail came into view.'),
  ('example-video-004', 1, 'I would stop at that bend just to take it in.'),
  ('example-video-005', 0, 'That glow changes the way the rock looks.'),
  ('example-video-005', 1, 'I watched again to catch the change in light.'),
  ('example-video-006', 0, 'I like how the daylight gives way to the streetlights.'),
  ('example-video-006', 1, 'The table outside was the detail I remembered.'),
  ('example-video-006', 2, 'Would you stay for another minute at the table, or follow the lights down the street?'),
  ('example-video-007', 0, 'I saw the plume before I noticed the hikers.'),
  ('example-video-007', 1, 'The sky stays such a clear blue behind it.'),
  ('example-video-008', 0, 'A slow ride under those pines sounds good today.'),
  ('example-video-008', 1, 'I spotted the water between the trees.'),
  ('example-video-009', 0, 'I liked the last stretch of light over the rooftops.'),
  ('example-video-009', 1, 'Seeing the whole city from one balcony feels strange in a good way.'),
  ('example-video-010', 0, 'The boat makes the ice look enormous.'),
  ('example-video-010', 1, 'I kept looking at the turquoise just below the surface.'),
  ('example-video-010', 2, 'The color changes at the waterline. Watch the bright sliver right beside the boat.')
) as edition(media_id, slot, body)
on conflict (video_id, position) do update
  set display_name = excluded.display_name, body = excluded.body, published_as_comment = true
  where (published.display_name, published.body, published.published_as_comment) is distinct from (excluded.display_name, excluded.body, true);

create or replace function liya_social_private.set_curated_starter_hidden(
  p_media_id text, p_position integer, p_hidden boolean, p_actor text
) returns boolean language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if (select auth.uid()) is not null or p_hidden is null or p_position is null or p_position < 0
     or char_length(trim(coalesce(p_actor, ''))) not between 1 and 120 then
    raise exception 'trusted database session and reviewer required';
  end if;
  perform 1 from public.liya_curated_video_prompts
    where video_id = p_media_id and position = p_position for update;
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

create policy liya_visible_prompt_media on public.liya_curated_video_prompts as restrictive for select to authenticated
using (exists (select 1 from public.liya_example_media m where m.id = liya_curated_video_prompts.video_id
  and liya_social_private.curated_object_visible(m.object_key)));

create view public.liya_media_editorial_comments with (security_invoker = true) as
select p.video_id as media_id, p.position, p.display_name, p.body
from public.liya_curated_video_prompts p
where p.published_as_comment and (select auth.uid()) is not null;
revoke all on public.liya_media_editorial_comments from public, anon, authenticated;
grant select on public.liya_media_editorial_comments to authenticated;

create policy liya_visible_comment_media on public.liya_video_comments as restrictive for select to authenticated
using (exists (select 1 from public.liya_example_media m where m.id = liya_video_comments.media_id
  and liya_social_private.curated_object_visible(m.object_key)));
alter policy video_comments_insert on public.liya_video_comments with check (
  owner_id = (select auth.uid()) and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
  and exists (select 1 from public.liya_example_media m where m.id = liya_video_comments.media_id
    and m.kind in ('photo','video') and liya_social_private.curated_object_visible(m.object_key))
);

create or replace function public.liya_media_engagement(p_media_ids text[])
returns table(media_id text, like_count bigint, comment_count bigint)
language sql stable security invoker set search_path = '' as $$
  select m.id, liya_social_private.media_like_total(m.id),
         (select count(*) from public.liya_video_comments c where c.media_id = m.id) +
         (select count(*) from public.liya_media_editorial_comments e where e.media_id = m.id)
  from public.liya_example_media m
  where (select auth.uid()) is not null
    and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
    and m.kind in ('photo', 'video') and m.id = any(p_media_ids)
    and liya_social_private.curated_object_visible(m.object_key);
$$;
create or replace function liya_social_private.photo_counts(p_media_id text)
returns table(like_count bigint, comment_count bigint)
language sql stable security invoker set search_path = '' as $$
  select e.like_count, e.comment_count from public.liya_media_engagement(array[p_media_id]) e
  where exists (select 1 from public.liya_example_media m where m.id = p_media_id and m.kind = 'photo');
$$;

alter policy video_comment_reports_insert on public.liya_video_comment_reports with check (
  reporter_id = (select auth.uid()) and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
  and exists (select 1 from public.liya_example_media m where m.id = liya_video_comment_reports.media_id
    and m.kind in ('photo','video') and liya_social_private.curated_object_visible(m.object_key))
  and (
    (preset_key is null and exists (
      select 1 from public.liya_video_comments c
      where c.id = liya_video_comment_reports.comment_id and c.media_id = liya_video_comment_reports.media_id
        and c.owner_id <> (select auth.uid()) and c.body = liya_video_comment_reports.body_snapshot
    ))
    or (comment_id is null and exists (
      select 1 from public.liya_media_editorial_comments e
      where e.media_id = liya_video_comment_reports.media_id
        and liya_video_comment_reports.preset_key = e.media_id || ':starter:' || e.position::text
        and e.body = liya_video_comment_reports.body_snapshot
    ))
  )
);

alter table public.liya_social_reports
  add column comment_id uuid,
  add column body_snapshot text,
  add constraint liya_social_comment_snapshot check (
    (comment_id is null and body_snapshot is null)
    or (comment_id is not null and body_snapshot is not null and char_length(trim(body_snapshot)) between 1 and 2000)
  );

alter policy social_reports_insert on public.liya_social_reports with check (
  reporter_id = (select auth.uid()) and target_user <> (select auth.uid())
  and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
  and (
    (comment_id is null
      and (exists (select 1 from public.liya_people p where p.id = liya_social_reports.target_user)
        or exists (select 1 from public.liya_blocks b where b.owner_id = (select auth.uid()) and b.target_id = liya_social_reports.target_user))
      and (post_id is null or exists (
        select 1 from public.liya_posts p where p.id = liya_social_reports.post_id and p.owner_id = liya_social_reports.target_user))
    )
    or (comment_id is not null and exists (
      select 1 from public.liya_post_comments c
      where c.id = liya_social_reports.comment_id and c.post_id = liya_social_reports.post_id
        and c.owner_id = liya_social_reports.target_user and c.body = liya_social_reports.body_snapshot
    ))
  )
);

update public.liya_feed_revision set revision = revision + 1 where id = true;
