-- =====================================================================
-- Trio — expense comments (run once in the Supabase SQL Editor).
-- Adds a comments table for the Split activity/detail view, with RLS so
-- only members of the expense's group can read/write, plus realtime.
-- Idempotent & safe to re-run. Requires schema.sql to have run first
-- (it uses the can_access_expense() helper).
-- =====================================================================

create table if not exists public.expense_comments (
  id         uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_expense_comments_expense
  on public.expense_comments(expense_id);

alter table public.expense_comments enable row level security;

drop policy if exists comments_select on public.expense_comments;
drop policy if exists comments_insert on public.expense_comments;
drop policy if exists comments_delete on public.expense_comments;

create policy comments_select on public.expense_comments for select to authenticated
  using (public.can_access_expense(expense_id));
create policy comments_insert on public.expense_comments for insert to authenticated
  with check (public.can_access_expense(expense_id) and user_id = auth.uid());
create policy comments_delete on public.expense_comments for delete to authenticated
  using (user_id = auth.uid());

-- Realtime so new comments appear for everyone instantly.
do $$
begin
  alter publication supabase_realtime add table public.expense_comments;
exception when duplicate_object then
  null;
end $$;
