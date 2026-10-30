-- Hashed receipts allow an interrupted deletion to be identified without retaining a user ID.
create table public.liya_deletion_receipts (
 request_hash text primary key check(char_length(request_hash)=64),
 status text not null check(status in ('pending','deleted')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.liya_deletion_receipts enable row level security;
revoke all on public.liya_deletion_receipts from public,anon,authenticated;
grant select,insert,update,delete on public.liya_deletion_receipts to service_role;
create function liya_social_private.account_active() returns boolean language sql stable security definer set search_path='' as $$
 select (select auth.uid()) is not null and exists(select 1 from auth.users u where u.id=(select auth.uid()));
$$;
revoke all on function liya_social_private.account_active() from public,anon,authenticated;
grant execute on function liya_social_private.account_active() to authenticated;
create policy liya_storage_active_account on storage.objects as restrictive for insert to authenticated with check ((select liya_social_private.account_active()));
