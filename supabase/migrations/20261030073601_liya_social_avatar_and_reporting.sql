alter table public.liya_people add column avatar_path text check (avatar_path is null or avatar_path like id::text || '/avatars/%');
create policy social_avatar_read on storage.objects for select to authenticated using(bucket_id='liya-user-media' and exists(select 1 from public.liya_people p where p.avatar_path = name));
drop policy social_reports_insert on public.liya_social_reports;
create policy social_reports_insert on public.liya_social_reports for insert to authenticated with check(
 reporter_id=(select auth.uid()) and
 (exists(select 1 from public.liya_people p where p.id=target_user) or exists(select 1 from public.liya_blocks b where b.owner_id=(select auth.uid()) and b.target_id=target_user)) and
 (post_id is null or exists(select 1 from public.liya_posts p where p.id=post_id and p.owner_id=target_user))
);
