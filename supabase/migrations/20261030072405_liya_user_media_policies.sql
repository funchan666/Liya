create policy liya_user_media_read_own on storage.objects for select to authenticated using (bucket_id = 'liya-user-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy liya_user_media_insert_own on storage.objects for insert to authenticated with check (bucket_id = 'liya-user-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
