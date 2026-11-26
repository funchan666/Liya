create table public.liya_curated_video_creators (
  video_id text primary key references public.liya_example_media(id),
  photo_id text not null references public.liya_example_media(id),
  display_name text not null, caption text not null
);
create table public.liya_curated_video_prompts (
  video_id text not null references public.liya_example_media(id),
  position integer not null check (position >= 0),
  display_name text not null, body text not null,
  primary key(video_id,position)
);
create table public.liya_curated_tree_prompts (
  position integer primary key check (position >= 0),
  mood text not null, body text not null
);
create index liya_curated_video_creators_photo_idx on public.liya_curated_video_creators(photo_id);
alter table public.liya_curated_video_creators enable row level security;
alter table public.liya_curated_video_prompts enable row level security;
alter table public.liya_curated_tree_prompts enable row level security;
create policy curated_video_creators_read on public.liya_curated_video_creators for select to authenticated using (true);
create policy curated_video_prompts_read on public.liya_curated_video_prompts for select to authenticated using (true);
create policy curated_tree_prompts_read on public.liya_curated_tree_prompts for select to authenticated using (true);
revoke all on public.liya_curated_video_creators, public.liya_curated_video_prompts, public.liya_curated_tree_prompts from anon, authenticated;
grant select on public.liya_curated_video_creators, public.liya_curated_video_prompts, public.liya_curated_tree_prompts to authenticated;
insert into public.liya_curated_video_creators(video_id,display_name,photo_id,caption) values
('example-video-001','Maya Bennett','example-photo-001','A little time by the sea.'),
('example-video-002','Elena Rivers','example-photo-002','Some views are worth the climb.'),
('example-video-003','Sofia Hayes','example-photo-003','Letting the noise wash away for a while.'),
('example-video-004','Theo Parker','example-photo-004','Taking the long way, one step at a time.'),
('example-video-005','Nora Ellis','example-photo-005','A moment to remember.'),
('example-video-006','Leo Martin','example-photo-006','A little sunshine on an ordinary day.'),
('example-video-007','Iris Chen','example-photo-007','Nature never stops surprising me.'),
('example-video-008','Noah Brooks','example-photo-008','A ride with a view.'),
('example-video-009','Ava Morgan','example-photo-009','A quiet moment above the city.'),
('example-video-010','Jules Carter','example-photo-010','Finding a little peace on the water.');
insert into public.liya_curated_video_prompts(video_id,position,display_name,body) values
('example-video-001',0,'Mia Lawson','That view is something else.'),
('example-video-001',1,'Jamie Reed','I could listen to the waves all day.'),
('example-video-002',0,'Avery Kim','The walk looks so worth it.'),
('example-video-002',1,'Alex Morgan','What a place to pause for a moment.'),
('example-video-003',0,'Sam Ellis','This feels like a breath of fresh air.'),
('example-video-003',1,'Leah Brooks','A little reset for the day.'),
('example-video-004',0,'Jordan Blake','The mountains are incredible.'),
('example-video-004',1,'Nina Hart','The kind of walk you remember.'),
('example-video-005',0,'Evan Cole','That looks like quite an adventure.'),
('example-video-005',1,'Lucy Bell','What a moment to capture.'),
('example-video-006',0,'Owen Price','Love the light in this moment.'),
('example-video-006',1,'Ivy Moore','A little sunshine makes a difference.'),
('example-video-007',0,'Max Turner','Nature really puts on a show.'),
('example-video-007',1,'Ella James','I would never forget that view.'),
('example-video-008',0,'Ryan Scott','A ride with a view like that? Yes please.'),
('example-video-008',1,'Zoe Hill','Looks like a lovely way to spend the day.'),
('example-video-009',0,'Finn Carter','That view is so peaceful.'),
('example-video-009',1,'Mila Grant','A quiet moment above the city.'),
('example-video-010',0,'Ethan Wells','The colour of the water is unreal.'),
('example-video-010',1,'Chloe Lane','This looks like a lovely escape.');
insert into public.liya_curated_tree_prompts(position,mood,body) values
(0,'mood-calm','Taking a breath before a busy day.'),
(1,'mood-blue','Today was harder than I expected.'),
(2,'mood-happy','A kind message made me smile.'),
(3,'mood-teal','Trying to take things one step at a time.'),
(4,'mood-yellow','I wish I could quiet my thoughts tonight.'),
(5,'mood-calm','The little things helped today.'),
(6,'mood-happy','I finally made time for an old friend.'),
(7,'mood-blue','Missing someone a little extra today.'),
(8,'mood-teal','A slow morning was just what I needed.'),
(9,'mood-upset','That conversation is still on my mind.'),
(10,'mood-yellow','Not every day needs a perfect ending.'),
(11,'mood-calm','A walk helped me clear my head.'),
(12,'mood-happy','There was sunshine on my way home.'),
(13,'mood-blue','I am learning to ask for help.'),
(14,'mood-teal','I need a little room to rest.'),
(15,'mood-upset','Hoping tomorrow feels a bit lighter.'),
(16,'mood-calm','Letting myself pause for a moment.'),
(17,'mood-happy','Good coffee and a quiet afternoon.'),
(18,'mood-yellow','Trying to be kinder to myself.'),
(19,'mood-blue','Some feelings are hard to put into words.');
