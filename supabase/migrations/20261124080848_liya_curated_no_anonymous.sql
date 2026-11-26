alter policy curated_video_creators_read on public.liya_curated_video_creators
  using (coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false');
alter policy curated_video_prompts_read on public.liya_curated_video_prompts
  using (coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false');
alter policy curated_tree_prompts_read on public.liya_curated_tree_prompts
  using (coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false');
