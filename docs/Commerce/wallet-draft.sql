-- Local design draft only. It has not been applied to the Supabase project.
-- The purchase verifier and spending/fulfillment transaction are separate work.
create schema liya_wallet_private;
revoke all on schema liya_wallet_private from public;
grant usage on schema liya_wallet_private to authenticated;

create table public.liya_wallets (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  balance bigint not null check (balance >= 0),
  welcome_pending boolean not null default true,
  updated_at timestamptz not null default now()
);
create table public.liya_coin_ledger (
  id bigint generated always as identity primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  operation_key text not null,
  kind text not null,
  delta bigint not null,
  balance_after bigint not null check (balance_after >= 0),
  created_at timestamptz not null default now(),
  unique(owner_id, operation_key)
);
create index liya_coin_ledger_owner_time on public.liya_coin_ledger(owner_id, created_at desc, id desc);
alter table public.liya_wallets enable row level security;
alter table public.liya_coin_ledger enable row level security;
revoke all on public.liya_wallets, public.liya_coin_ledger from public, anon, authenticated;
grant select on public.liya_wallets, public.liya_coin_ledger to authenticated;
create policy wallet_read_own on public.liya_wallets for select to authenticated
  using (owner_id = (select auth.uid()));
create policy ledger_read_own on public.liya_coin_ledger for select to authenticated
  using (owner_id = (select auth.uid()));

-- The only credit in this draft is the fixed, once-per-account welcome gift.
create function liya_wallet_private.claim_welcome()
returns table(balance bigint, welcome_pending boolean)
language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  created_owner uuid;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  insert into public.liya_wallets(owner_id, balance, welcome_pending)
  values(current_user_id, 600, true)
  on conflict (owner_id) do nothing
  returning owner_id into created_owner;
  if created_owner is not null then
    insert into public.liya_coin_ledger(owner_id, operation_key, kind, delta, balance_after)
    values(current_user_id, 'welcome', 'welcome', 600, 600);
  end if;
  return query select w.balance, w.welcome_pending
    from public.liya_wallets w where w.owner_id = current_user_id;
end;
$$;
revoke all on function liya_wallet_private.claim_welcome() from public, anon, authenticated;
grant execute on function liya_wallet_private.claim_welcome() to authenticated;

create function public.liya_claim_welcome()
returns table(balance bigint, welcome_pending boolean)
language sql security invoker set search_path = '' as $$
  select * from liya_wallet_private.claim_welcome();
$$;
revoke all on function public.liya_claim_welcome() from public, anon, authenticated;
grant execute on function public.liya_claim_welcome() to authenticated;

create function liya_wallet_private.acknowledge_welcome()
returns void language plpgsql security definer set search_path = '' as $$
declare current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  update public.liya_wallets set welcome_pending = false, updated_at = now()
    where owner_id = current_user_id and welcome_pending = true;
end;
$$;
revoke all on function liya_wallet_private.acknowledge_welcome() from public, anon, authenticated;
grant execute on function liya_wallet_private.acknowledge_welcome() to authenticated;

create function public.liya_acknowledge_welcome()
returns void language sql security invoker set search_path = '' as $$
  select liya_wallet_private.acknowledge_welcome();
$$;
revoke all on function public.liya_acknowledge_welcome() from public, anon, authenticated;
grant execute on function public.liya_acknowledge_welcome() to authenticated;
