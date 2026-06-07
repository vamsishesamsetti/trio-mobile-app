# Trio — Supabase setup (one-time, free)

Trio uses a free Supabase project for auth + database + realtime sync. This is the **only**
manual step needed to give the app a backend. Free tier easily covers <10 users.

## 1. Create the project
1. Go to https://supabase.com → sign in (GitHub is fine) → **New project**.
2. Name it `trio` (anything works). Choose a strong **database password** (save it).
3. Pick the region closest to you. Click **Create** and wait ~2 min for it to provision.

## 2. Run the SQL (in order)
In the dashboard, open **SQL Editor → New query**, then paste & **Run** each file, in order:

1. `schema.sql`   – tables, indexes, helper functions, realtime
2. `policies.sql` – Row Level Security (each user only sees their own / their groups' data)
3. `seed.sql`     – auto-creates a profile + default account + categories on sign-up
4. `comments.sql` – expense comments table (used by the Split Activity / detail view)

All are idempotent (safe to re-run).

## 3. Confirm email settings (so you can log in without email confirmation while testing)
**Authentication → Providers → Email**: keep **Email** enabled.
**Authentication → Sign In / Providers → Email → "Confirm email"**: for a <10-person private
app you can turn **OFF** "Confirm email" so accounts work instantly. (Turn back on later if
you want.) Save.

## 4. Grab your API credentials
**Project Settings → API**:
- **Project URL**  → looks like `https://xxxxxxxx.supabase.co`
- **anon public key** → long JWT starting with `eyJ...`

Paste both into the app config (the app reads them via `--dart-define`, see `trio/README.md`).
The anon key is safe to ship in a client app — RLS is what protects the data.

## 5. (Optional) Local CLI workflow
If you install the Supabase CLI later, you can run all three files with:
```
supabase db push   # or: psql "$DATABASE_URL" -f schema.sql -f policies.sql -f seed.sql
```
