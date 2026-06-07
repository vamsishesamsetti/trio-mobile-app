-- =====================================================================
-- Trio — new-user bootstrap   (run AFTER schema.sql & policies.sql)
-- On sign-up, auto-create a profile + a default "Cash" account +
-- default income/expense categories so the app is usable immediately.
-- Idempotent.
-- =====================================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, email, default_currency)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    new.email,
    'USD'
  )
  on conflict (id) do nothing;

  insert into public.accounts (user_id, name, type, opening_balance, currency, icon, color)
  values (new.id, 'Cash', 'cash', 0, 'USD', 'wallet', '#4CAF50');

  insert into public.categories (user_id, name, kind, icon, color) values
    (new.id, 'Food & Drink',      'expense', 'restaurant',     '#FF7043'),
    (new.id, 'Groceries',         'expense', 'shopping_cart',  '#66BB6A'),
    (new.id, 'Transport',         'expense', 'directions_car', '#42A5F5'),
    (new.id, 'Shopping',          'expense', 'shopping_bag',   '#AB47BC'),
    (new.id, 'Bills & Utilities', 'expense', 'receipt',        '#EF5350'),
    (new.id, 'Entertainment',     'expense', 'movie',          '#FFA726'),
    (new.id, 'Health',            'expense', 'favorite',       '#EC407A'),
    (new.id, 'Rent',              'expense', 'home',           '#8D6E63'),
    (new.id, 'Travel',            'expense', 'flight',         '#26C6DA'),
    (new.id, 'Other',             'expense', 'category',       '#78909C');

  insert into public.categories (user_id, name, kind, icon, color) values
    (new.id, 'Salary',       'income', 'payments',      '#26A69A'),
    (new.id, 'Freelance',    'income', 'work',          '#5C6BC0'),
    (new.id, 'Investments',  'income', 'trending_up',   '#66BB6A'),
    (new.id, 'Gift',         'income', 'card_giftcard', '#9CCC65'),
    (new.id, 'Other Income', 'income', 'attach_money',  '#78909C');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
