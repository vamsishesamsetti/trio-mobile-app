-- =====================================================================
-- Trio — Row Level Security policies   (run AFTER schema.sql)
-- Idempotent: drops existing policies before recreating.
-- =====================================================================

-- Enable RLS on every table
alter table public.profiles        enable row level security;
alter table public.accounts        enable row level security;
alter table public.categories      enable row level security;
alter table public.transactions    enable row level security;
alter table public.budgets         enable row level security;
alter table public.recurring_rules enable row level security;
alter table public.groups          enable row level security;
alter table public.group_members   enable row level security;
alter table public.expenses        enable row level security;
alter table public.expense_splits  enable row level security;
alter table public.settlements     enable row level security;
alter table public.projects        enable row level security;
alter table public.time_entries    enable row level security;

-- ---------------------------------------------------------------------
-- PROFILES: readable by any signed-in user (to show member names);
-- writable only by the owner.
-- ---------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_update on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);
create policy profiles_insert on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------------
-- PERSONAL tables: owner-only full access (select/insert/update/delete)
-- accounts, categories, transactions, budgets, recurring_rules,
-- projects, time_entries
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'accounts','categories','transactions','budgets',
    'recurring_rules','projects','time_entries'
  ] loop
    execute format('drop policy if exists %I_own on public.%I;', t, t);
    execute format(
      'create policy %I_own on public.%I for all to authenticated
         using (user_id = auth.uid()) with check (user_id = auth.uid());',
      t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- GROUPS: members (and the creator) can read; creator manages.
-- ---------------------------------------------------------------------
drop policy if exists groups_select on public.groups;
drop policy if exists groups_insert on public.groups;
drop policy if exists groups_update on public.groups;
drop policy if exists groups_delete on public.groups;
create policy groups_select on public.groups for select to authenticated
  using (created_by = auth.uid() or public.is_group_member(id));
create policy groups_insert on public.groups for insert to authenticated
  with check (created_by = auth.uid());
create policy groups_update on public.groups for update to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy groups_delete on public.groups for delete to authenticated
  using (created_by = auth.uid());

-- ---------------------------------------------------------------------
-- GROUP_MEMBERS: members see the roster; owner adds/edits; users can
-- see and remove their own membership (leave group).
-- ---------------------------------------------------------------------
drop policy if exists gm_select on public.group_members;
drop policy if exists gm_insert on public.group_members;
drop policy if exists gm_update on public.group_members;
drop policy if exists gm_delete on public.group_members;
create policy gm_select on public.group_members for select to authenticated
  using (user_id = auth.uid() or public.is_group_member(group_id) or public.is_group_owner(group_id));
create policy gm_insert on public.group_members for insert to authenticated
  with check (public.is_group_owner(group_id) or user_id = auth.uid());
create policy gm_update on public.group_members for update to authenticated
  using (public.is_group_owner(group_id));
create policy gm_delete on public.group_members for delete to authenticated
  using (public.is_group_owner(group_id) or user_id = auth.uid());

-- ---------------------------------------------------------------------
-- EXPENSES: any group member reads; member creates (as themselves);
-- only the creator edits/deletes.
-- ---------------------------------------------------------------------
drop policy if exists expenses_select on public.expenses;
drop policy if exists expenses_insert on public.expenses;
drop policy if exists expenses_update on public.expenses;
drop policy if exists expenses_delete on public.expenses;
create policy expenses_select on public.expenses for select to authenticated
  using (public.is_group_member(group_id));
create policy expenses_insert on public.expenses for insert to authenticated
  with check (public.is_group_member(group_id) and created_by = auth.uid());
create policy expenses_update on public.expenses for update to authenticated
  using (created_by = auth.uid()) with check (public.is_group_member(group_id));
create policy expenses_delete on public.expenses for delete to authenticated
  using (created_by = auth.uid());

-- ---------------------------------------------------------------------
-- EXPENSE_SPLITS: visible/writable to members of the parent expense's group.
-- ---------------------------------------------------------------------
drop policy if exists splits_select on public.expense_splits;
drop policy if exists splits_write  on public.expense_splits;
create policy splits_select on public.expense_splits for select to authenticated
  using (public.can_access_expense(expense_id));
create policy splits_write on public.expense_splits for all to authenticated
  using (public.can_access_expense(expense_id))
  with check (public.can_access_expense(expense_id));

-- ---------------------------------------------------------------------
-- SETTLEMENTS: group members read/record/delete.
-- ---------------------------------------------------------------------
drop policy if exists settlements_select on public.settlements;
drop policy if exists settlements_write  on public.settlements;
create policy settlements_select on public.settlements for select to authenticated
  using (public.is_group_member(group_id));
create policy settlements_write on public.settlements for all to authenticated
  using (public.is_group_member(group_id))
  with check (public.is_group_member(group_id));
