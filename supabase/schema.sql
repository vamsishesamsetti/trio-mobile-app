-- =====================================================================
-- Trio — database schema (tables, indexes, helper functions, realtime)
-- Run order: 1) schema.sql  2) policies.sql  3) seed.sql
-- Paste into Supabase Dashboard → SQL Editor and run, or use the CLI.
-- Idempotent: safe to re-run.
-- =====================================================================

create extension if not exists "pgcrypto";

-- =====================================================================
-- PROFILES (1 row per auth user)
-- =====================================================================
create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  display_name     text,
  email            text,                      -- mirrored from auth for member lookup
  avatar_url       text,
  default_currency text not null default 'USD',
  created_at       timestamptz not null default now()
);

-- If upgrading an older deploy, make sure the column exists.
alter table public.profiles add column if not exists email text;
create index if not exists idx_profiles_email on public.profiles(lower(email));

-- =====================================================================
-- MONEY TRACKER (personal — scoped by user_id)
-- =====================================================================
create table if not exists public.accounts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  type            text not null default 'cash',          -- cash/bank/card/wallet
  opening_balance numeric(14,2) not null default 0,
  currency        text not null default 'USD',
  icon            text,
  color           text,
  archived        boolean not null default false,
  created_at      timestamptz not null default now()
);

create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  kind       text not null,                              -- income/expense
  icon       text,
  color      text,
  parent_id  uuid references public.categories(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.transactions (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  account_id          uuid not null references public.accounts(id) on delete cascade,
  category_id         uuid references public.categories(id) on delete set null,
  type                text not null,                     -- income/expense/transfer
  amount              numeric(14,2) not null check (amount >= 0),
  currency            text not null default 'USD',
  txn_date            date not null default current_date,
  note                text,
  transfer_account_id uuid references public.accounts(id) on delete set null,
  created_at          timestamptz not null default now()
);

create table if not exists public.budgets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  category_id uuid references public.categories(id) on delete cascade,
  amount      numeric(14,2) not null check (amount > 0),
  period      text not null default 'monthly',           -- weekly/monthly/yearly
  start_date  date not null default current_date,
  created_at  timestamptz not null default now()
);

create table if not exists public.recurring_rules (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  account_id    uuid not null references public.accounts(id) on delete cascade,
  category_id   uuid references public.categories(id) on delete set null,
  type          text not null,                           -- income/expense
  amount        numeric(14,2) not null check (amount >= 0),
  note          text,
  frequency     text not null,                           -- daily/weekly/monthly/yearly
  next_run_date date not null,
  created_at    timestamptz not null default now()
);

-- =====================================================================
-- SPLITWISE (shared — scoped by group membership)
-- =====================================================================
create table if not exists public.groups (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  created_by       uuid not null references auth.users(id) on delete cascade,
  default_currency text not null default 'USD',
  created_at       timestamptz not null default now()
);

create table if not exists public.group_members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  user_id      uuid references auth.users(id) on delete cascade,
  invite_email text,                                     -- for members not yet signed up
  role         text not null default 'member',           -- owner/member
  created_at   timestamptz not null default now(),
  unique (group_id, user_id)
);

create table if not exists public.expenses (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  paid_by      uuid not null references auth.users(id) on delete cascade,
  description  text not null,
  amount       numeric(14,2) not null check (amount > 0),
  currency     text not null default 'USD',
  expense_date date not null default current_date,
  split_type   text not null default 'equal',            -- equal/exact/percent/shares
  category     text,
  created_by   uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now()
);

create table if not exists public.expense_splits (
  id          uuid primary key default gen_random_uuid(),
  expense_id  uuid not null references public.expenses(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  owed_amount numeric(14,2) not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.settlements (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups(id) on delete cascade,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  amount     numeric(14,2) not null check (amount > 0),
  note       text,
  settled_at timestamptz not null default now()
);

-- =====================================================================
-- HOURS TRACKER (personal — scoped by user_id)
-- =====================================================================
create table if not exists public.projects (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  client      text,
  hourly_rate numeric(12,2) not null default 0,
  currency    text not null default 'USD',
  color       text,
  archived    boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.time_entries (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  project_id       uuid not null references public.projects(id) on delete cascade,
  task             text,
  started_at       timestamptz not null,
  ended_at         timestamptz,                          -- null while timer running
  duration_seconds integer,
  billable         boolean not null default true,
  note             text,
  created_at       timestamptz not null default now()
);

-- =====================================================================
-- INDEXES
-- =====================================================================
create index if not exists idx_accounts_user        on public.accounts(user_id);
create index if not exists idx_categories_user       on public.categories(user_id);
create index if not exists idx_transactions_user     on public.transactions(user_id);
create index if not exists idx_transactions_date      on public.transactions(user_id, txn_date);
create index if not exists idx_budgets_user          on public.budgets(user_id);
create index if not exists idx_recurring_user        on public.recurring_rules(user_id);
create index if not exists idx_group_members_group   on public.group_members(group_id);
create index if not exists idx_group_members_user    on public.group_members(user_id);
create index if not exists idx_expenses_group        on public.expenses(group_id);
create index if not exists idx_expense_splits_exp    on public.expense_splits(expense_id);
create index if not exists idx_expense_splits_user   on public.expense_splits(user_id);
create index if not exists idx_settlements_group     on public.settlements(group_id);
create index if not exists idx_projects_user         on public.projects(user_id);
create index if not exists idx_time_entries_user     on public.time_entries(user_id);
create index if not exists idx_time_entries_project  on public.time_entries(project_id);

-- =====================================================================
-- HELPER FUNCTIONS (SECURITY DEFINER — bypass RLS to avoid recursion)
-- =====================================================================
create or replace function public.is_group_member(_group_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = _group_id and gm.user_id = auth.uid()
  );
$$;

create or replace function public.is_group_owner(_group_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.groups g
    where g.id = _group_id and g.created_by = auth.uid()
  );
$$;

create or replace function public.can_access_expense(_expense_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from public.expenses e
    join public.group_members gm on gm.group_id = e.group_id
    where e.id = _expense_id and gm.user_id = auth.uid()
  );
$$;

-- =====================================================================
-- REALTIME (live updates for shared Splitwise data)
-- =====================================================================
do $$
begin
  perform 1 from pg_publication where pubname = 'supabase_realtime';
  if found then
    alter publication supabase_realtime add table public.expenses;
    alter publication supabase_realtime add table public.expense_splits;
    alter publication supabase_realtime add table public.settlements;
    alter publication supabase_realtime add table public.group_members;
  end if;
exception when duplicate_object then
  null; -- tables already in publication
end $$;
