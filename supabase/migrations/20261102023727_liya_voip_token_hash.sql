-- The device token itself never appears in PostgREST query parameters.
alter table public.liya_voip_devices add column token_hash text generated always as (encode(extensions.digest(token,'sha256'),'hex')) stored;
create unique index liya_voip_devices_token_hash on public.liya_voip_devices(token_hash);
