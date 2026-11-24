# Mardan Digital Hub — JANJAMZ

A responsive local-business discovery website for District Mardan, together with a private JANJAMZ workspace for team tasks, client management, projects and directory submissions.

## What's included

- `index.html` — public website and `/admin` workspace shell.
- `config.js` — Supabase connection settings (currently blank).
- `config.example.js` — copyable configuration template.
- `_redirects` — Cloudflare Pages rewrite so `/admin` opens the same HTML app.
- `assets/nadeem-jamal.jpg` — portrait supplied for Nadeem Jamal.
- `assets/ashraf-ali.jpg` — portrait cropped from Ashraf Ali's supplied CV.
- `supabase/schema.sql` — database tables, role helpers, RLS, indexes, and Storage policies.
- `supabase/seed.sql` — eight industry groups and eight JANJAMZ service categories (not client records).
- `supabase/functions/invite-member/index.ts` — owner-only secure team invitation function.

## Important current-state notes

1. **Supabase is not connected yet.** `config.js` is intentionally blank because no Mardan Digital Hub Supabase project URL or publishable key was supplied. The public website works with its supplied sample entries, and `/admin` has a clearly labeled local demo preview.
2. The demo admin workspace is **not private** and is stored only in the current browser. Never enter real client, member, password, or financial information in demo mode.
3. Eighteen local business reference records are included: names from the supplied brief plus public listing lookup results dated 23 November 2026. Two publicly listed service-provider references are also included. All remain explicitly unverified; public directory details can be incomplete or change, and no GPS coordinates have been invented. Some review counts differ from the initial brief because the newer lookup returned different totals for KFC Mardan and Cheezious; the dataset records that discrepancy in each entry.
4. The eight industry cards describe target sectors, **not eight confirmed JANJAMZ clients**. Demo clients shown in the demo dashboard are fictitious examples.
5. The first version includes working directory search/filtering, map view, lead form, listing/provider submissions, Supabase sign-in, role-aware task assignment and review, project-team assignment, client records, leads, projects, owner-only member invitations, and owner-only submission review. Finance database tables are included, but invoice/quotation/payment screens are a foundation rather than a completed payment product. No payment gateway is connected.
6. The five team profiles on the public site use only the descriptions supplied. No unprovided member email addresses, passwords, phone numbers, qualifications or work history have been invented.

## Local reference listings and verification

The initial frontend includes a small starter set of Mardan listings so the directory is not empty. The additional names, listing addresses, phone numbers, ratings and review totals were retrieved from public business-search listings on 23 November 2026. Each is marked `verified: false` in the frontend data. The Place IDs are retained where supplied to support Google Maps search links. These records are reference leads, not proof of business ownership, licensing, availability, or current operating status. Confirm details with each business and obtain any necessary permission before treating a listing as an endorsed or verified directory entry.

The public listing lookup returned slightly different review totals than the original brief for KFC Mardan and Cheezious. The site uses the lookup totals for those two records and preserves the earlier brief values in `review_count_note`. Qasim Chapli Kabab's name and review count remain user-supplied because a matching structured listing was not confirmed in that lookup.

## Run the public site locally

Use a local web server (opening the file directly with `file://` is not recommended because the map, browser modules and Supabase connections need an HTTP origin).

```bash
cd mardan-digital-hub
python3 -m http.server 8080
```

Open `http://localhost:8080` in your browser. For the local private-workspace preview, use `http://localhost:8080/#admin` (the Python test server does not process the Cloudflare `/admin` rewrite). On Cloudflare Pages, the `_redirects` file serves `/admin` directly.

## Connect Supabase

### 1. Create a dedicated Supabase project

Create a new Supabase project for Mardan Digital Hub. This package does not modify any existing JANJAMZ or SprintTech project.

### 2. Install the database schema

In Supabase Dashboard → SQL Editor:

1. Open `supabase/schema.sql` and run the complete script.
2. Open `supabase/seed.sql` and run it.
3. Confirm that the tables and Storage buckets were created.

The schema enables RLS on the exposed application tables. It uses three app roles: `owner`, `manager`, and `member`.

### 3. Create the first owner account

Create the owner account through Supabase Dashboard → Authentication → Users. Use Nadeem Jamal's confirmed company login email and set a secure password. The email address for this login was not supplied in the conversation, so do not assume that `janjamzhq@gmail.com` is his personal login; that is the company contact address.

After the Auth user is created, copy its UUID from Authentication → Users and run this once in SQL Editor, replacing the UUID:

```sql
update public.profiles
set full_name = 'Nadeem Jamal',
    job_title = 'Founder & Director',
    role = 'owner'
where id = 'REPLACE-WITH-AUTH-USER-UUID';
```

The Auth trigger creates a profile with the default `member` role. The trusted SQL update above bootstraps the first owner. Do not expose a general owner-registration form.

### 4. Configure the browser client

Edit `config.js`:

```js
window.JANJAMZ_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co',
  supabasePublishableKey: 'sb_publishable_...'
};
```

Use the project's **publishable** key (or its legacy anon key if that is what the project provides). It is designed for browser use only when RLS is correctly enabled. Never paste a Supabase `service_role` or secret key into `config.js`, `index.html`, GitHub, or any browser-side file.

### 5. Deploy the secure member invitation function

Install and authenticate the Supabase CLI, then from this project directory. The `supabase/config.toml` file is already included:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy invite-member
```

In Supabase Dashboard → Edge Functions → Secrets (or using the CLI), configure:

- `SUPABASE_PUBLISHABLE_KEY` — the project's publishable/anon key for validating the caller.
- `SUPABASE_SECRET_KEY` — the server-side secret key. If the project still uses the legacy service role key, configure `SUPABASE_SERVICE_ROLE_KEY` instead.

The platform supplies `SUPABASE_URL` to Edge Functions. The invitation function checks the caller's Auth identity and verifies that their database profile has the active `owner` role before inviting a `member` or `manager`. The secret key remains server-side.

### 6. Invite the JANJAMZ team

Sign in at `/admin` as the owner. Open Team Members → Invite Member and enter each person's actual email address. Email addresses were not supplied for the members, so add them only after confirming them with each person.

Suggested roles:

- Nadeem Jamal — `owner`
- Zubair Jamal — `manager`
- Muhammad Idrees — `member`
- Ashraf Ali — `member`
- Tariq Masaoud — `member`

The manager can coordinate client records, leads, projects and tasks and can see a limited team directory for assignment. Only the owner can view full profile records, invite members, review and publish business/provider submissions, or access finance records. Members can see their own assigned tasks and update progress; they cannot access other members' private profiles.

### 7. Deploy the website

Upload the project directory to Cloudflare Pages (or another static host). Keep the `assets/` folder, `config.js`, and `_redirects` in the deployed root. Add your real domain to the Supabase Auth redirect URL allowlist before inviting members. The site is designed to be hosted at the domain root because the `/admin` rewrite and `/config.js` path are root-relative.

## Data and security model

- Public visitors can view approved business/provider records and approved portfolio items.
- Visitors can submit business/provider applications and new enquiries; those records remain pending/new until a manager or owner reviews them.
- `owner` can manage the whole workspace and financial records.
- `manager` can coordinate client records, leads, projects and tasks, and assign project work. The manager sees only a limited team directory, not private member emails/phones. Directory submissions and finance remain owner-only.
- `member` can view their own profile and assigned tasks, then update task progress for those assignments.
- RLS enforces access in Postgres. Hiding navigation buttons is not treated as a security boundary.
- Storage has a public avatar bucket and private work-files bucket. Private work-file object names should begin with the uploading member's Auth UUID as the first path folder.
- Business reviews and listing applications are pending until reviewed.
- Demo-mode data is browser-local only and never becomes a shared team database.

## Operational checks before real use

- Confirm the first owner account and all five team members' email addresses.
- Add real client records only after the client has agreed to be recorded.
- Review each business's name, contact, hours and coordinates before publishing it.
- Test login and access using one owner, one manager and one member account.
- Confirm that members cannot query other members' profiles or financial data.
- Run Supabase Security and Performance Advisors after installing the schema and address any warnings relevant to your project's configuration.
- Turn on Realtime for the `tasks` table if you want the owner dashboard to refresh when task records change.
- Add a CAPTCHA or server-side rate limiting before promoting the public lead and listing forms to a high-traffic production site.
- Add backups, retention rules and a privacy notice before collecting substantial client information.
