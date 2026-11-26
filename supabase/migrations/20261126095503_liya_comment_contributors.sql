alter table public.liya_example_media
  add column portrait_byline text
    check (portrait_byline is null or (kind = 'photo' and length(trim(portrait_byline)) between 1 and 80));

update public.liya_example_media as portrait
set portrait_byline = credit.byline
from (values
  ('example-photo-031', 'Mia Lawson'),
  ('example-photo-032', 'Jamie Reed'),
  ('example-photo-033', 'Avery Kim'),
  ('example-photo-034', 'Sam Ellis'),
  ('example-photo-035', 'Nina Hart'),
  ('example-photo-036', 'Leah Brooks'),
  ('example-photo-037', 'Finn Carter'),
  ('example-photo-038', 'Ivy Moore'),
  ('example-photo-039', 'Lucy Bell')
) as credit(portrait_id, byline)
where portrait.id = credit.portrait_id and portrait.kind = 'photo';

alter table public.liya_curated_video_prompts
  add column contributor_portrait_id text references public.liya_example_media(id);

with credits(media_id, portrait_numbers) as (values
  ('example-photo-001', array[31,34]),
  ('example-photo-002', array[32,37,35]),
  ('example-photo-003', array[36]),
  ('example-photo-004', array[38,33]),
  ('example-photo-005', array[39]),
  ('example-photo-006', array[34,35]),
  ('example-photo-007', array[37,36]),
  ('example-photo-008', array[31]),
  ('example-photo-009', array[32,38]),
  ('example-photo-010', array[33,39,34]),
  ('example-photo-011', array[35]),
  ('example-photo-013', array[37,31]),
  ('example-photo-014', array[38]),
  ('example-photo-015', array[32,36]),
  ('example-photo-016', array[39]),
  ('example-photo-017', array[33,34]),
  ('example-photo-018', array[35]),
  ('example-photo-019', array[31,36,32]),
  ('example-photo-020', array[38,37]),
  ('example-video-001', array[31,32]),
  ('example-video-002', array[33,34]),
  ('example-video-003', array[35,36,39]),
  ('example-video-004', array[37,38]),
  ('example-video-005', array[39,31]),
  ('example-video-006', array[32,33,35]),
  ('example-video-007', array[34,36]),
  ('example-video-008', array[37,39]),
  ('example-video-009', array[38,35]),
  ('example-video-010', array[36,32,33])
)
update public.liya_curated_video_prompts as comment
set contributor_portrait_id = portrait.id, display_name = portrait.portrait_byline
from credits
cross join lateral unnest(credits.portrait_numbers) with ordinality as slot(portrait_number, ordinal)
join public.liya_example_media as portrait on portrait.id = 'example-photo-' || lpad(slot.portrait_number::text, 3, '0')
where comment.video_id = credits.media_id and comment.position = slot.ordinal - 1
  and comment.published_as_comment and portrait.portrait_byline is not null;

create or replace view public.liya_media_editorial_comments with (security_invoker = true) as
select comment.video_id as media_id, comment.position,
       coalesce(portrait.portrait_byline, comment.display_name) as display_name, comment.body,
       case when portrait.id is not null and liya_social_private.curated_object_visible(portrait.object_key)
            then portrait.id end as portrait_media_id
from public.liya_curated_video_prompts as comment
left join public.liya_example_media as portrait on portrait.id = comment.contributor_portrait_id
where comment.published_as_comment and (select auth.uid()) is not null;

update public.liya_feed_revision set revision = revision + 1 where id = true;
