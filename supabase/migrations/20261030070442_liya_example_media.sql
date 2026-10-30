-- Shared illustrative content: these entries are not login accounts or real people.
create table public.liya_example_media (
  id text primary key,
  kind text not null check (kind in ('photo', 'video')),
  sort_order integer not null check (sort_order >= 0),
  object_key text not null unique,
  size_bytes bigint not null check (size_bytes > 0),
  sha256 text not null check (char_length(sha256) = 64),
  unique(kind, sort_order)
);
alter table public.liya_example_media enable row level security;
revoke all on public.liya_example_media from anon, authenticated;
grant select on public.liya_example_media to authenticated;
create policy liya_example_media_read on public.liya_example_media
  for select to authenticated using (true);

insert into public.liya_example_media (id, kind, sort_order, object_key, size_bytes, sha256) values
  ('example-photo-001', 'photo', 0, 'photo/example_photo_001.jpg', 143670, '9943ea463eaa7953e18202d1fade9b466a41c7f2d7703f9fbc1f57315ecebebe'),
  ('example-photo-002', 'photo', 1, 'photo/example_photo_002.jpg', 135244, 'ebbb77ac4dad5902aec459ecfa0ffced15ebf95cb7361d735714462015569003'),
  ('example-photo-003', 'photo', 2, 'photo/example_photo_003.jpg', 260319, 'f23fcb0bf9abfed346718888da0637cf928eaa2422be554a22061b6370f00b62'),
  ('example-photo-004', 'photo', 3, 'photo/example_photo_004.jpg', 249633, 'ed68bee93f63b2882b52202506fdfcf56759eeb47c0955f8a17cab3e284c4da5'),
  ('example-photo-005', 'photo', 4, 'photo/example_photo_005.jpg', 192558, '37e726ff8cdef31beb6837e44874f0c5dde66daa87fbe003f3ebdfe09aef91d5'),
  ('example-photo-006', 'photo', 5, 'photo/example_photo_006.jpg', 333133, 'a535cbaf814aee433caf3a8bc6cb8175b82919432ecd798184c125c9b862cba3'),
  ('example-photo-007', 'photo', 6, 'photo/example_photo_007.jpg', 110699, 'b5e3188290b9a416ef531b4b79cce49062de041a5837eafce90bd047c5171c9f'),
  ('example-photo-008', 'photo', 7, 'photo/example_photo_008.jpg', 271415, 'dd5a5f6ded57d19d3f17290ee641d5115a9b7d53a0b518b36c89aa3e8606a144'),
  ('example-photo-009', 'photo', 8, 'photo/example_photo_009.jpg', 191108, '1da68a3d19646858a04560d6862afc2a87b14b38843ce7ccc2e791f76851509f'),
  ('example-photo-010', 'photo', 9, 'photo/example_photo_010.jpg', 216272, 'd58ffd3f0373c188da6e552cc77680bab7e95ec45dc8f92b4b4417daacb251e8'),
  ('example-photo-011', 'photo', 10, 'photo/example_photo_011.jpg', 159755, 'fdfb8a9bc15fd59222acee01208883b9ddb3e6fb7493bc4f2c917bdd8d7ab6be'),
  ('example-photo-012', 'photo', 11, 'photo/example_photo_012.jpg', 209231, '67df92a32bb7278c03b7172d63ddd49a8e7d8cb14a9ec3902f37cd16787ec9f6'),
  ('example-photo-013', 'photo', 12, 'photo/example_photo_013.jpg', 262976, '7e7ea52c4c7889291e5ad40e9d788a5c9471163b20f72a245a5f68394ad9d10f'),
  ('example-photo-014', 'photo', 13, 'photo/example_photo_014.jpg', 279773, 'f3c62237de55a5f299c681726f782150ada717b8c118d55c9c70a1c1ce8f3533'),
  ('example-photo-015', 'photo', 14, 'photo/example_photo_015.jpg', 223726, 'd623a32f1463780c004f71e6271b1e9dfe7b60c1917d92827063cbdfb2406a70'),
  ('example-photo-016', 'photo', 15, 'photo/example_photo_016.jpg', 128389, 'e38a8b3553541cd0899ba6fd729d3a97f544f0b67c4ec5c4efbb8e502f77ac12'),
  ('example-photo-017', 'photo', 16, 'photo/example_photo_017.jpg', 100016, '92d07b360dca233630367d80cfc471d19138c099895e623303f054018ac84aba'),
  ('example-photo-018', 'photo', 17, 'photo/example_photo_018.jpg', 54922, 'ff22f0d98989db4c9366837a653b770106713e04b7fb1da6ae3bafb362e4f990'),
  ('example-photo-019', 'photo', 18, 'photo/example_photo_019.jpg', 345186, '38091190cd9eb6a43d4f69f29c84f7cc3514bef0366ff2fbe00faf3e9a22ea95'),
  ('example-photo-020', 'photo', 19, 'photo/example_photo_020.jpg', 175438, '4e8a6b045e78973052ac2c8567782ae663f60a0781e152fd02d0b69663a88c8d'),
  ('example-photo-021', 'photo', 20, 'photo/example_photo_021.jpg', 111741, '9f384d71adf07feaada3c247f39396b28b1105982310721987979a3e98cbe1e2'),
  ('example-photo-022', 'photo', 21, 'photo/example_photo_022.jpg', 439422, '65454399ae8464c9eaea53d907d35db66cd2295991af035b771a989e263bb46b'),
  ('example-photo-023', 'photo', 22, 'photo/example_photo_023.jpg', 214531, '282e99b4db9b7ea218e0727b99cb3623c289d6c5ba510547dc2042ff759a0326'),
  ('example-photo-024', 'photo', 23, 'photo/example_photo_024.jpg', 213447, '579cde3dfc0acc36ee946f87f120a3942dbbeaab579aaca163be82023e05bdad'),
  ('example-photo-025', 'photo', 24, 'photo/example_photo_025.jpg', 334146, '2d145ecae57974214783d79821daf2ff77ae9352409efd86c01d7eb6220749ab'),
  ('example-photo-026', 'photo', 25, 'photo/example_photo_026.jpg', 260206, 'fe5210d905b1df1fcc35b1d7f6287283085e96d0c879ea3607f3f46fdeb5c86f'),
  ('example-photo-027', 'photo', 26, 'photo/example_photo_027.jpg', 213881, '16cf5643ac1f0b9062b84ad5384e52ca8df687f70558044cbc14a1396687de06'),
  ('example-photo-028', 'photo', 27, 'photo/example_photo_028.jpg', 231101, '9d0b5eedc61bb5fa011ed92abbdf0567748ac0fdf81280f90e3a6711a460a1a4'),
  ('example-photo-029', 'photo', 28, 'photo/example_photo_029.jpg', 228898, 'b616a1d20b53ded1f6273b2a74361c6d1869eb33ac1db46fd4ebb4dd8e91cf3f'),
  ('example-photo-030', 'photo', 29, 'photo/example_photo_030.jpg', 578938, '94de7f610ef8479cde8d219f635fc11f37e1f785fc0ae62d980114ed2e291be8'),
  ('example-photo-031', 'photo', 30, 'photo/example_photo_031.jpg', 252771, '51c4d0f63580f9213b58d718389ee76b285efd0cbb3b6ab1198492c6b877f407'),
  ('example-photo-032', 'photo', 31, 'photo/example_photo_032.jpg', 310236, 'f0a5a9f2e71c25e41e78608101c0068ee07bb385e7a295282ab11049ce302f7f'),
  ('example-photo-033', 'photo', 32, 'photo/example_photo_033.jpg', 249481, 'd93b307dde27340217b956b0d1fec33a1de3b8cbccbc3aec3d0c8f977dccbffc'),
  ('example-photo-034', 'photo', 33, 'photo/example_photo_034.jpg', 198272, '48141fc7592182ff9f1179e154afd371698f690c194af0be492bec129640825d'),
  ('example-photo-035', 'photo', 34, 'photo/example_photo_035.jpg', 130884, '5a9e70f8437d4f2c8f103209871a13d985f6e057df1286376b4c5bab80cfa4f4'),
  ('example-photo-036', 'photo', 35, 'photo/example_photo_036.jpg', 366611, 'a59b3ff1df52db6a8487c9b1eee50d0beb2ed889a828786f64811575568fc8f0'),
  ('example-photo-037', 'photo', 36, 'photo/example_photo_037.jpg', 89290, '03f6279d9c15962ed99eafcc51080fa86cf19b750dc87005c9372a33dcfe3937'),
  ('example-photo-038', 'photo', 37, 'photo/example_photo_038.jpg', 142339, '99b64e72535cb8ac83814e89236d162ddab74c970c5171d1d5dcaf1240abec10'),
  ('example-photo-039', 'photo', 38, 'photo/example_photo_039.jpg', 207886, '63e9eba678e4093595bb90ef4a6bd283c1ee2c41f828623321f021d899fb7ba3'),
  ('example-photo-040', 'photo', 39, 'photo/example_photo_040.jpg', 294097, '2303d2fa0f61efdc31759af8ef6d53e072e4912e4e5b99991ceb31b8cbfdf8e5'),
  ('example-video-001', 'video', 0, 'video/example_video_001.mp4', 6090668, 'b3d9b1dfc24750a916ca7f4b6eebde8e6343843f2805ecf683da54bda48a2885'),
  ('example-video-002', 'video', 1, 'video/example_video_002.mp4', 3750779, 'ec990d8c1ac81206259cba58035454c7a484bdaff319f065645ced8e33c1caad'),
  ('example-video-003', 'video', 2, 'video/example_video_003.mp4', 4115886, 'd96d5f8dd2680f36e1ee2ae9cee2891c48834108a558cacc797ca7882451274f'),
  ('example-video-004', 'video', 3, 'video/example_video_004.mp4', 7766552, '146212fc900d18aaff2882d7e31b5e97d139ebb055685e587f1a891c7aa545fd'),
  ('example-video-005', 'video', 4, 'video/example_video_005.mp4', 3699671, 'f9249bd9d1d6712efaff6b0d82665a16e2a2c6a8ca565d56d60c80b826369e10'),
  ('example-video-006', 'video', 5, 'video/example_video_006.mp4', 5825003, '20141c3c71d490d9833fbbeecfcbdfbb04d33c1c17d4d520c1a131dbd11722a0'),
  ('example-video-007', 'video', 6, 'video/example_video_007.mp4', 3066682, 'b5b08bb2712c2414941a132db7ed44732d87ed317d2409eff42dab2a070d89d8'),
  ('example-video-008', 'video', 7, 'video/example_video_008.mp4', 8876415, 'a53b1a373aaa51c6b2106f2e8e3cc005c00196a52f884e66f8f0d0e27db3671a'),
  ('example-video-009', 'video', 8, 'video/example_video_009.mp4', 2679417, '7b2544338c27c42661b51cc3816415de7d04ade48ccc6b76fb44714f3ce45943'),
  ('example-video-010', 'video', 9, 'video/example_video_010.mp4', 2857146, 'ffbbe7207e01052bd2be79abbb19d86c950b393aff56ab0f308642741b12d537');

-- Only catalogued examples are readable; the bucket remains private, and no
-- client upload/update/delete permission is granted by this policy.
create policy liya_example_objects_read on storage.objects
  for select to authenticated
  using (bucket_id = 'liya-example-media' and exists (
    select 1 from public.liya_example_media m where m.object_key = storage.objects.name
  ));
