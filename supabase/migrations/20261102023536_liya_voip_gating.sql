create or replace function liya_social_private.enqueue_voip() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.liya_voip_config where id and enabled) then return null; end if;
 insert into public.liya_voip_jobs(call_id) values(new.id) on conflict(call_id) do nothing;
 perform liya_social_private.dispatch_voip(new.id);
 return null;
end $$;
