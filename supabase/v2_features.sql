-- =====================================================================
-- Trio v2 — soft-delete audit, expense editing, receipt photos.
-- Run once in the Supabase SQL Editor (after schema.sql/policies.sql).
-- Idempotent & safe to re-run.
-- =====================================================================

-- 1) Soft-delete audit columns (keep history of who deleted & when) ----
alter table public.expenses    add column if not exists deleted_at timestamptz;
alter table public.expenses    add column if not exists deleted_by uuid references auth.users(id);
alter table public.expenses    add column if not exists receipt_url text;
alter table public.settlements add column if not exists deleted_at timestamptz;
alter table public.settlements add column if not exists deleted_by uuid references auth.users(id);

-- 2) Let any group member edit / delete expenses (Splitwise-style) ------
drop policy if exists expenses_update on public.expenses;
create policy expenses_update on public.expenses for update to authenticated
  using (public.is_group_member(group_id))
  with check (public.is_group_member(group_id));

drop policy if exists expenses_delete on public.expenses;
create policy expenses_delete on public.expenses for delete to authenticated
  using (public.is_group_member(group_id));

-- 3) Storage bucket for receipt photos ---------------------------------
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', true)
on conflict (id) do nothing;

-- Signed-in users can upload; bucket is public so URLs render anywhere.
drop policy if exists "receipts upload" on storage.objects;
drop policy if exists "receipts read"   on storage.objects;
drop policy if exists "receipts delete" on storage.objects;
create policy "receipts upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts');
create policy "receipts read" on storage.objects for select to public
  using (bucket_id = 'receipts');
create policy "receipts delete" on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and owner = auth.uid());
