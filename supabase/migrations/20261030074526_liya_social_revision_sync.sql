create table public.liya_feed_revision (id boolean primary key default true check(id), revision bigint not null default 0);
insert into public.liya_feed_revision(id,revision) values(true,0);
create table public.liya_user_revisions (owner_id uuid primary key references auth.users(id) on delete cascade, revision bigint not null default 0);
alter table public.liya_feed_revision enable row level security;
alter table public.liya_user_revisions enable row level security;
revoke all on public.liya_feed_revision, public.liya_user_revisions from public, anon, authenticated;
grant select on public.liya_feed_revision, public.liya_user_revisions to authenticated;
create policy liya_feed_revision_read on public.liya_feed_revision for select to authenticated using (true);
create policy liya_user_revision_read on public.liya_user_revisions for select to authenticated using (owner_id=(select auth.uid()));
create function liya_social_private.touch_user_revision(who uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if who is not null and exists(select 1 from auth.users u where u.id=who) then
  insert into public.liya_user_revisions(owner_id,revision) values(who,1)
  on conflict(owner_id) do update set revision=public.liya_user_revisions.revision+1;
 end if;
exception when foreign_key_violation then null;
end;
$$;
revoke all on function liya_social_private.touch_user_revision(uuid) from public,anon,authenticated;
create function liya_social_private.signal_feed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.liya_feed_revision set revision=revision+1 where id=true;
 return null;
end;
$$;
revoke all on function liya_social_private.signal_feed() from public,anon,authenticated;
create function liya_social_private.signal_pair() returns trigger language plpgsql security definer set search_path='' as $$
declare a uuid; b uuid;
begin
 if tg_table_name='liya_messages' then
  if tg_op='DELETE' then a:=old.sender_id; b:=old.recipient_id; else a:=new.sender_id; b:=new.recipient_id; end if;
 else
  if tg_op='DELETE' then a:=old.owner_id; b:=old.target_id; else a:=new.owner_id; b:=new.target_id; end if;
 end if;
 perform liya_social_private.touch_user_revision(a);
 if b is distinct from a then perform liya_social_private.touch_user_revision(b); end if;
 return null;
end;
$$;
revoke all on function liya_social_private.signal_pair() from public,anon,authenticated;
create function liya_social_private.signal_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then perform liya_social_private.touch_user_revision(old.owner_id);
 else perform liya_social_private.touch_user_revision(new.owner_id); end if;
 return null;
end;
$$;
revoke all on function liya_social_private.signal_notification() from public,anon,authenticated;
create trigger liya_sync_posts after insert or update or delete on public.liya_posts for each statement execute function liya_social_private.signal_feed();
create trigger liya_sync_people after insert or update or delete on public.liya_people for each statement execute function liya_social_private.signal_feed();
create trigger liya_sync_comments after insert or update or delete on public.liya_post_comments for each statement execute function liya_social_private.signal_feed();
create trigger liya_sync_likes after insert or update or delete on public.liya_post_likes for each statement execute function liya_social_private.signal_feed();
create trigger liya_sync_follows after insert or delete on public.liya_follows for each row execute function liya_social_private.signal_pair();
create trigger liya_sync_blocks after insert or delete on public.liya_blocks for each row execute function liya_social_private.signal_pair();
create trigger liya_sync_messages after insert or update or delete on public.liya_messages for each row execute function liya_social_private.signal_pair();
create trigger liya_sync_notifications after insert or update or delete on public.liya_social_notifications for each row execute function liya_social_private.signal_notification();
alter publication supabase_realtime add table public.liya_feed_revision;
alter publication supabase_realtime add table public.liya_user_revisions;
