create table public.liya_social_notifications (
 id bigint generated always as identity primary key,
 owner_id uuid not null references public.liya_people(id) on delete cascade,
 actor_id uuid not null references public.liya_people(id) on delete cascade,
 kind text not null check (kind in ('follow','like','comment')),
 post_id uuid references public.liya_posts(id) on delete cascade,
 is_read boolean not null default false,
 created_at timestamptz not null default now()
);
create index liya_social_notifications_owner on public.liya_social_notifications(owner_id,created_at desc,id desc);
alter table public.liya_social_notifications enable row level security;
revoke all on public.liya_social_notifications from public,anon,authenticated;
grant select on public.liya_social_notifications to authenticated;
grant update(is_read) on public.liya_social_notifications to authenticated;
create policy notifications_read on public.liya_social_notifications for select to authenticated using(owner_id=(select auth.uid()) and not liya_social_private.blocked(actor_id));
create policy notifications_update on public.liya_social_notifications for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create function liya_social_private.notify_interaction() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid; action text; related_post uuid;
begin
 if (select auth.uid()) is null or new.owner_id <> (select auth.uid()) then raise exception 'authentication required'; end if;
 if tg_table_name = 'liya_follows' then recipient := new.target_id; action := 'follow'; related_post := null;
 else select p.owner_id into recipient from public.liya_posts p where p.id = new.post_id;
  action := case when tg_table_name='liya_post_likes' then 'like' else 'comment' end; related_post := new.post_id;
 end if;
 if recipient is not null and recipient <> new.owner_id and not exists(select 1 from public.liya_blocks b where (b.owner_id=recipient and b.target_id=new.owner_id) or (b.owner_id=new.owner_id and b.target_id=recipient)) then
  insert into public.liya_social_notifications(owner_id,actor_id,kind,post_id) values(recipient,new.owner_id,action,related_post);
 end if;
 return new;
end;
$$;
revoke all on function liya_social_private.notify_interaction() from public,anon,authenticated;
create trigger liya_notify_follow after insert on public.liya_follows for each row execute function liya_social_private.notify_interaction();
create trigger liya_notify_like after insert on public.liya_post_likes for each row execute function liya_social_private.notify_interaction();
create trigger liya_notify_comment after insert on public.liya_post_comments for each row execute function liya_social_private.notify_interaction();
create function liya_social_private.remove_blocked_follows() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or new.owner_id <> (select auth.uid()) then raise exception 'authentication required'; end if;
 delete from public.liya_follows where (owner_id=new.owner_id and target_id=new.target_id) or (owner_id=new.target_id and target_id=new.owner_id);
 return new;
end;
$$;
revoke all on function liya_social_private.remove_blocked_follows() from public,anon,authenticated;
create trigger liya_block_removes_follows after insert on public.liya_blocks for each row execute function liya_social_private.remove_blocked_follows();
alter publication supabase_realtime add table public.liya_social_notifications;
