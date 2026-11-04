-- Apple-signed transactions are verified by the Edge Function before this service-only operation.
-- Production and sandbox credits are separate; sandbox transactions can never fund production.
create table if not exists public.liya_sandbox_wallets (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0),
  welcome_pending boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.liya_sandbox_wallets enable row level security;
revoke all on public.liya_sandbox_wallets from public, anon, authenticated;
grant select on public.liya_sandbox_wallets to authenticated;
drop policy if exists liya_sandbox_wallet_read on public.liya_sandbox_wallets;
create policy liya_sandbox_wallet_read on public.liya_sandbox_wallets for select to authenticated
  using (owner_id = (select auth.uid()));

create or replace function public.liya_claim_sandbox_welcome()
returns table(balance bigint, welcome_pending boolean)
language plpgsql security definer set search_path = '' as $$
declare current_owner uuid := auth.uid();
begin
  if current_owner is null then raise exception 'authentication required'; end if;
  insert into public.liya_sandbox_wallets(owner_id,balance,welcome_pending)
    values(current_owner,600,true) on conflict(owner_id) do nothing;
  return query select w.balance,w.welcome_pending from public.liya_sandbox_wallets w where w.owner_id=current_owner;
end $$;
revoke all on function public.liya_claim_sandbox_welcome() from public, anon;
grant execute on function public.liya_claim_sandbox_welcome() to authenticated;

create or replace function public.liya_acknowledge_sandbox_welcome()
returns void language plpgsql security definer set search_path = '' as $$
declare current_owner uuid := auth.uid();
begin
  if current_owner is null then raise exception 'authentication required'; end if;
  update public.liya_sandbox_wallets set welcome_pending=false,updated_at=now() where owner_id=current_owner;
end $$;
revoke all on function public.liya_acknowledge_sandbox_welcome() from public, anon;
grant execute on function public.liya_acknowledge_sandbox_welcome() to authenticated;

create schema if not exists liya_purchase_private;
revoke all on schema liya_purchase_private from public, anon, authenticated;
create table if not exists liya_purchase_private.apple_transactions (
  environment text not null check (environment in ('Production', 'Sandbox')),
  transaction_id text not null check (transaction_id ~ '^[0-9]{1,30}$'),
  owner_id uuid references auth.users(id) on delete set null,
  product_id text not null,
  coins integer not null check (coins > 0),
  created_at timestamptz not null default now(),
  primary key (environment, transaction_id)
);
alter table liya_purchase_private.apple_transactions enable row level security;
revoke all on liya_purchase_private.apple_transactions from public, anon, authenticated;

create or replace function public.liya_credit_apple_purchase(
  p_owner uuid, p_environment text, p_transaction_id text, p_product_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  amount integer;
  inserted boolean := false;
  balance_value bigint;
  previous_owner uuid;
  previous_product text;
begin
  if p_owner is null or p_environment not in ('Production','Sandbox')
     or p_transaction_id !~ '^[0-9]{1,30}$' then raise exception 'invalid purchase'; end if;
  amount := case p_product_id
    when 'ceyarlaxiuojqsbi' then 450 when 'gxaojqvpvmykrgif' then 950
    when 'hzlqemvjatucwprd' then 1500 when 'hqahzvljpcaltfnm' then 2700
    when 'npdkdztghlqpfxnr' then 5800 when 'qwnbrlxesdvyampt' then 9000
    when 'czyghtwgjcswnuvl' then 12500 when 'jemidcjpjteygrfy' then 34000
    when 'qmubwwcjusfbmlpw' then 72000 else null end;
  if amount is null then raise exception 'invalid product'; end if;
  insert into liya_purchase_private.apple_transactions(environment,transaction_id,owner_id,product_id,coins)
    values(p_environment,p_transaction_id,p_owner,p_product_id,amount)
    on conflict(environment,transaction_id) do nothing returning true into inserted;
  if not coalesce(inserted,false) then
    select owner_id, product_id into previous_owner, previous_product
      from liya_purchase_private.apple_transactions where environment=p_environment and transaction_id=p_transaction_id;
    if previous_owner is distinct from p_owner or previous_product is distinct from p_product_id then
      raise exception 'purchase ownership mismatch';
    end if;
    return jsonb_build_object('status','already_delivered','environment',p_environment);
  end if;
  if p_environment = 'Production' then
    update public.liya_wallets set balance=balance+amount,updated_at=now()
      where owner_id=p_owner returning balance into balance_value;
    if balance_value is null then raise exception 'wallet not ready'; end if;
    insert into public.liya_coin_ledger(owner_id,operation_key,kind,delta,balance_after)
      values(p_owner,'apple:' || p_transaction_id,'apple_purchase',amount,balance_value);
  else
    insert into public.liya_sandbox_wallets(owner_id,balance) values(p_owner,amount)
      on conflict(owner_id) do update set balance=public.liya_sandbox_wallets.balance+excluded.balance,updated_at=now()
      returning balance into balance_value;
  end if;
  return jsonb_build_object('status','delivered','environment',p_environment,'balance',balance_value);
end $$;
revoke all on function public.liya_credit_apple_purchase(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.liya_credit_apple_purchase(uuid,text,text,text) to service_role;

do $$ begin
  if not exists (select 1 from pg_catalog.pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='liya_sandbox_wallets') then
    alter publication supabase_realtime add table public.liya_sandbox_wallets;
  end if;
end $$;
