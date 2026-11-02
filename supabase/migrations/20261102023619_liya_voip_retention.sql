create or replace function liya_social_private.retry_voip() returns void language plpgsql security definer set search_path='' as $$
declare j record;
begin
 if not exists(select 1 from public.liya_voip_config where id and enabled) then return; end if;
 for j in select v.call_id from public.liya_voip_jobs v join public.liya_calls c on c.id=v.call_id
  where v.delivered_at is null and v.next_attempt<=now() and c.status='ringing' and c.expires_at>now() order by v.next_attempt limit 25 loop
  perform liya_social_private.dispatch_voip(j.call_id);
 end loop;
 delete from public.liya_voip_jobs v using public.liya_calls c
  where c.id=v.call_id and c.status<>'ringing' and c.updated_at<now()-interval '24 hours';
end $$;
