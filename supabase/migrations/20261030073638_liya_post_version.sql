alter table public.liya_posts add column updated_at timestamptz not null default now();
create function liya_social_private.touch_post() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at := now(); return new; end;
$$;
revoke all on function liya_social_private.touch_post() from public,anon,authenticated;
create trigger liya_post_touch before update on public.liya_posts for each row execute function liya_social_private.touch_post();
