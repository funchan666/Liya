create schema liya_social_private;
revoke all on schema liya_social_private from public;
grant usage on schema liya_social_private to authenticated;

create table public.liya_people (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (char_length(trim(display_name)) between 1 and 80),
 signature text not null default '' check (char_length(signature) <= 500),
 created_at timestamptz not null default now()
);
create table public.liya_blocks (
 owner_id uuid not null references public.liya_people(id) on delete cascade,
 target_id uuid not null references public.liya_people(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(owner_id,target_id), check(owner_id <> target_id)
);
create index liya_blocks_target on public.liya_blocks(target_id,owner_id);
create function liya_social_private.blocked(other uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select (select auth.uid()) is null or exists(select 1 from public.liya_blocks b where (b.owner_id=(select auth.uid()) and b.target_id=other) or (b.target_id=(select auth.uid()) and b.owner_id=other));
$$;
revoke all on function liya_social_private.blocked(uuid) from public, anon;
grant execute on function liya_social_private.blocked(uuid) to authenticated;
create function liya_social_private.paths_valid(owner uuid, item uuid, paths text[]) returns boolean language sql immutable set search_path = '' as $$
 select coalesce(array_length(paths,1),0) <= 9 and not exists(select 1 from unnest(paths) p where p is null or p not like owner::text || '/social/' || item::text || '/%');
$$;
revoke all on function liya_social_private.paths_valid(uuid,uuid,text[]) from public, anon;
grant execute on function liya_social_private.paths_valid(uuid,uuid,text[]) to authenticated;

create table public.liya_posts (
 id uuid primary key, owner_id uuid not null references public.liya_people(id) on delete cascade,
 body text not null default '' check (char_length(body)<=4000), tags text[] not null default '{}',
 media_paths text[] not null default '{}', media_kinds text[] not null default '{}',
 created_at timestamptz not null default now(),
 check(cardinality(tags)<=6), check(cardinality(media_paths)=cardinality(media_kinds)),
 check(media_kinds <@ array['photo','video']::text[]),
 check(char_length(trim(body))>0 or cardinality(media_paths)>0),
 check(liya_social_private.paths_valid(owner_id,id,media_paths))
);
create index liya_posts_created on public.liya_posts(created_at desc,id desc);
create index liya_posts_owner on public.liya_posts(owner_id,created_at desc);
create table public.liya_post_likes (
 owner_id uuid not null references public.liya_people(id) on delete cascade,
 post_id uuid not null references public.liya_posts(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(owner_id,post_id)
);
create index liya_post_likes_post on public.liya_post_likes(post_id);
create table public.liya_post_comments (
 id uuid primary key, owner_id uuid not null references public.liya_people(id) on delete cascade,
 post_id uuid not null references public.liya_posts(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default now()
);
create index liya_post_comments_post on public.liya_post_comments(post_id,created_at,id);
create table public.liya_follows (
 owner_id uuid not null references public.liya_people(id) on delete cascade,
 target_id uuid not null references public.liya_people(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(owner_id,target_id), check(owner_id<>target_id)
);
create index liya_follows_target on public.liya_follows(target_id,owner_id);
create table public.liya_messages (
 id uuid primary key, sender_id uuid not null references public.liya_people(id) on delete cascade,
 recipient_id uuid not null references public.liya_people(id) on delete cascade,
 body text not null default '' check(char_length(body)<=4000),
 media_paths text[] not null default '{}', media_kinds text[] not null default '{}',
 created_at timestamptz not null default now(), check(sender_id<>recipient_id),
 check(cardinality(media_paths)=cardinality(media_kinds)), check(media_kinds <@ array['photo','video']::text[]),
 check(char_length(trim(body))>0 or cardinality(media_paths)>0),
 check(liya_social_private.paths_valid(sender_id,id,media_paths))
);
create index liya_messages_sender on public.liya_messages(sender_id,created_at desc,id);
create index liya_messages_recipient on public.liya_messages(recipient_id,created_at desc,id);
create table public.liya_social_reports (
 id uuid primary key, reporter_id uuid not null references auth.users(id) on delete cascade,
 target_user uuid not null references auth.users(id) on delete cascade,
 post_id uuid references public.liya_posts(id) on delete set null,
 reason text not null check (reason in ('Sexual content','Harassment','Discrimination','Incorrect content','Other')),
 created_at timestamptz not null default now(), check(reporter_id<>target_user)
);
create index liya_social_reports_created on public.liya_social_reports(created_at);

alter table public.liya_people enable row level security;
alter table public.liya_blocks enable row level security;
alter table public.liya_posts enable row level security;
alter table public.liya_post_likes enable row level security;
alter table public.liya_post_comments enable row level security;
alter table public.liya_follows enable row level security;
alter table public.liya_messages enable row level security;
alter table public.liya_social_reports enable row level security;
revoke all on public.liya_people,public.liya_blocks,public.liya_posts,public.liya_post_likes,public.liya_post_comments,public.liya_follows,public.liya_messages,public.liya_social_reports from public, anon, authenticated;
grant select,insert,update on public.liya_people to authenticated;
grant select,insert,delete on public.liya_blocks,public.liya_post_likes,public.liya_post_comments,public.liya_follows,public.liya_messages to authenticated;
grant select,insert,update,delete on public.liya_posts to authenticated;
grant select,insert on public.liya_social_reports to authenticated;
create policy people_read on public.liya_people for select to authenticated using (id=(select auth.uid()) or not liya_social_private.blocked(id));
create policy people_insert on public.liya_people for insert to authenticated with check(id=(select auth.uid()));
create policy people_update on public.liya_people for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy blocks_read on public.liya_blocks for select to authenticated using(owner_id=(select auth.uid()));
create policy blocks_insert on public.liya_blocks for insert to authenticated with check(owner_id=(select auth.uid()));
create policy blocks_delete on public.liya_blocks for delete to authenticated using(owner_id=(select auth.uid()));
create policy posts_read on public.liya_posts for select to authenticated using(owner_id=(select auth.uid()) or not liya_social_private.blocked(owner_id));
create policy posts_insert on public.liya_posts for insert to authenticated with check(owner_id=(select auth.uid()));
create policy posts_update on public.liya_posts for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy posts_delete on public.liya_posts for delete to authenticated using(owner_id=(select auth.uid()));
create policy post_likes_read on public.liya_post_likes for select to authenticated using(exists(select 1 from public.liya_posts p where p.id=post_id) and (owner_id=(select auth.uid()) or not liya_social_private.blocked(owner_id)));
create policy post_likes_insert on public.liya_post_likes for insert to authenticated with check(owner_id=(select auth.uid()) and exists(select 1 from public.liya_posts p where p.id=post_id));
create policy post_likes_delete on public.liya_post_likes for delete to authenticated using(owner_id=(select auth.uid()));
create policy comments_read on public.liya_post_comments for select to authenticated using(exists(select 1 from public.liya_posts p where p.id=post_id) and (owner_id=(select auth.uid()) or not liya_social_private.blocked(owner_id)));
create policy comments_insert on public.liya_post_comments for insert to authenticated with check(owner_id=(select auth.uid()) and exists(select 1 from public.liya_posts p where p.id=post_id));
create policy comments_delete on public.liya_post_comments for delete to authenticated using(owner_id=(select auth.uid()));
create policy follows_read on public.liya_follows for select to authenticated using((owner_id=(select auth.uid()) or target_id=(select auth.uid())) and not liya_social_private.blocked(case when owner_id=(select auth.uid()) then target_id else owner_id end));
create policy follows_insert on public.liya_follows for insert to authenticated with check(owner_id=(select auth.uid()) and not liya_social_private.blocked(target_id));
create policy follows_delete on public.liya_follows for delete to authenticated using(owner_id=(select auth.uid()));
create policy messages_read on public.liya_messages for select to authenticated using((sender_id=(select auth.uid()) or recipient_id=(select auth.uid())) and not liya_social_private.blocked(case when sender_id=(select auth.uid()) then recipient_id else sender_id end));
create policy messages_insert on public.liya_messages for insert to authenticated with check(sender_id=(select auth.uid()) and not liya_social_private.blocked(recipient_id));
create policy messages_delete on public.liya_messages for delete to authenticated using(sender_id=(select auth.uid()));
create policy social_reports_read on public.liya_social_reports for select to authenticated using(reporter_id=(select auth.uid()));
create policy social_reports_insert on public.liya_social_reports for insert to authenticated with check(reporter_id=(select auth.uid()) and not liya_social_private.blocked(target_user));
create policy social_media_read on storage.objects for select to authenticated using(bucket_id='liya-user-media' and (exists(select 1 from public.liya_posts p where name=any(p.media_paths)) or exists(select 1 from public.liya_messages m where name=any(m.media_paths))));
alter publication supabase_realtime add table public.liya_messages;
