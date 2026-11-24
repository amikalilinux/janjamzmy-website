-- Mardan Digital Hub / JANJAMZ
-- Supabase PostgreSQL schema. Run once in the Supabase SQL Editor.
-- Before using the app, create the first Auth user and promote that UUID to owner
-- using the bootstrap SQL shown in README.md.

create extension if not exists pgcrypto;
create schema if not exists app_private;
revoke all on schema app_private from public, anon;
grant usage on schema app_private to authenticated;

-- -----------------------------------------------------------------------------
-- Role helpers. They are kept in a non-exposed schema. SECURITY DEFINER is used
-- only for narrowly scoped role lookup; callers can only inspect their own role.
-- -----------------------------------------------------------------------------
create or replace function app_private.current_role()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_role text;
begin
  if (select auth.uid()) is null then return null; end if;
  select p.role into v_role
  from public.profiles p
  where p.id = (select auth.uid())
  limit 1;
  return v_role;
end;
$$;
revoke all on function app_private.current_role() from public, anon;
grant execute on function app_private.current_role() to authenticated;

create or replace function app_private.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select coalesce(app_private.current_role() = 'owner', false); $$;
revoke all on function app_private.is_owner() from public, anon;
grant execute on function app_private.is_owner() to authenticated;

create or replace function app_private.is_manager_or_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select coalesce(app_private.current_role() in ('owner','manager'), false); $$;
revoke all on function app_private.is_manager_or_owner() from public, anon;
grant execute on function app_private.is_manager_or_owner() to authenticated;

create or replace function app_private.can_access_project(p_project_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then return false; end if;
  return coalesce(app_private.current_role() in ('owner','manager'), false)
    or exists (
      select 1 from public.project_members pm
      where pm.project_id = p_project_id
        and pm.user_id = (select auth.uid())
    );
end;
$$;
revoke all on function app_private.can_access_project(uuid) from public, anon;
grant execute on function app_private.can_access_project(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Profiles and automatic profile creation for newly invited Auth users.
-- New accounts are always members until an owner changes their role through the
-- secure invite-member Edge Function or a trusted SQL bootstrap operation.
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text not null default 'JANJAMZ Team Member',
  job_title text,
  role text not null default 'member' check (role in ('owner','manager','member')),
  avatar_url text,
  skills text[] not null default '{}',
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A limited team directory lets the manager assign tasks without exposing private
-- member emails, phone numbers or skill metadata. Only owner and manager can read it.
create table if not exists public.team_directory (
  id uuid primary key references public.profiles(id) on delete cascade,
  full_name text not null,
  job_title text,
  role text not null check (role in ('owner','manager','member')),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

create or replace function app_private.sync_team_directory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.team_directory (id,full_name,job_title,role,is_active,updated_at)
  values (new.id,new.full_name,new.job_title,new.role,new.is_active,now())
  on conflict (id) do update set
    full_name=excluded.full_name,
    job_title=excluded.job_title,
    role=excluded.role,
    is_active=excluded.is_active,
    updated_at=now();
  return new;
end;
$$;
revoke all on function app_private.sync_team_directory() from public, anon, authenticated;
drop trigger if exists sync_team_directory_after_profile_change on public.profiles;
create trigger sync_team_directory_after_profile_insert
after insert on public.profiles
for each row execute function app_private.sync_team_directory();
create trigger sync_team_directory_after_profile_update
after update of full_name,job_title,role,is_active on public.profiles
for each row execute function app_private.sync_team_directory();

create or replace function app_private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''), split_part(coalesce(new.email,'Team Member'),'@',1)),
    'member'
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
revoke all on function app_private.handle_new_auth_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function app_private.handle_new_auth_user();

-- -----------------------------------------------------------------------------
-- Public directory and provider records. Only approved rows are publicly visible.
-- -----------------------------------------------------------------------------
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  urdu_name text,
  category text not null,
  sub_category text,
  area text not null,
  tehsil text,
  plus_code text,
  address text,
  owner_name text,
  phone text,
  email text,
  website text,
  place_id text,
  rating numeric(2,1) check (rating is null or rating between 1 and 5),
  review_count integer not null default 0 check (review_count >= 0),
  price_range text,
  opening_hours jsonb not null default '{}'::jsonb,
  highlights text[] not null default '{}',
  description text,
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  verified boolean not null default false,
  status text not null default 'pending' check (status in ('pending','approved','rejected','archived')),
  created_by uuid references public.profiles(id) on delete set null,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.service_providers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  urdu_name text,
  service text not null,
  skills text[] not null default '{}',
  area text not null,
  tehsil text,
  phone text,
  experience_years integer check (experience_years is null or experience_years >= 0),
  price text,
  availability text,
  description text,
  rating numeric(2,1) check (rating is null or rating between 1 and 5),
  review_count integer not null default 0 check (review_count >= 0),
  verified boolean not null default false,
  status text not null default 'pending' check (status in ('pending','approved','rejected','archived')),
  created_by uuid references public.profiles(id) on delete set null,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_submissions (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  category text not null,
  area text not null,
  contact_name text,
  phone text not null,
  email text,
  address text,
  website text,
  note text,
  submitted_by uuid references auth.users(id) on delete set null default auth.uid(),
  status text not null default 'pending' check (status in ('pending','reviewing','approved','rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.provider_submissions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  service text not null,
  phone text not null,
  area text not null,
  skills text[] not null default '{}',
  experience_years integer,
  price text,
  note text,
  submitted_by uuid references auth.users(id) on delete set null default auth.uid(),
  status text not null default 'pending' check (status in ('pending','reviewing','approved','rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.business_reviews (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null default auth.uid(),
  display_name text not null,
  rating integer not null check (rating between 1 and 5),
  review_text text not null check (char_length(review_text) between 3 and 2000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- CRM, project management and task allocation.
-- -----------------------------------------------------------------------------
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  industry text,
  contact_name text,
  phone text,
  whatsapp text,
  email text,
  address text,
  area text,
  website text,
  social_links jsonb not null default '{}'::jsonb,
  requirements text,
  notes text,
  manager_id uuid references public.profiles(id) on delete set null,
  status text not null default 'lead' check (status in ('new_lead','lead','contacted','meeting_scheduled','proposal_sent','negotiation','active','completed','inactive')),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.client_contacts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  contact_type text not null default 'note',
  subject text,
  body text not null,
  follow_up_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  client_id uuid references public.clients(id) on delete set null,
  description text,
  project_type text,
  status text not null default 'planning' check (status in ('planning','design','development','testing','client_review','revision','delivered','on_hold','cancelled')),
  progress integer not null default 0 check (progress between 0 and 100),
  budget numeric(14,2),
  start_date date,
  deadline date,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  manager_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_members (
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null default auth.uid(),
  assigned_at timestamptz not null default now(),
  primary key (project_id,user_id)
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  client_id uuid references public.clients(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  assigned_to uuid not null references public.profiles(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  priority text not null default 'medium' check (priority in ('urgent','high','medium','low')),
  status text not null default 'assigned' check (status in ('not_started','assigned','in_progress','under_review','revision_required','completed','cancelled')),
  due_date date,
  estimated_hours numeric(7,2) check (estimated_hours is null or estimated_hours >= 0),
  actual_hours numeric(7,2) check (actual_hours is null or actual_hours >= 0),
  progress integer not null default 0 check (progress between 0 and 100),
  deliverables text,
  member_notes text,
  submitted_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  comment text not null check (char_length(comment) between 1 and 3000),
  created_at timestamptz not null default now()
);

create table if not exists public.task_attachments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  file_name text not null,
  storage_path text not null,
  content_type text,
  size_bytes bigint,
  created_at timestamptz not null default now()
);

create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  link text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Leads, estimates, invoices, payments and approved portfolio items.
-- -----------------------------------------------------------------------------
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  business_name text,
  phone text not null,
  email text,
  industry text,
  service_interest text,
  message text,
  status text not null default 'new' check (status in ('new','contacted','qualified','proposal_sent','converted','closed')),
  assigned_to uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.quotations (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  quote_number text not null unique,
  title text not null,
  items jsonb not null default '[]'::jsonb,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  tax numeric(14,2) not null default 0 check (tax >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  currency text not null default 'PKR',
  status text not null default 'draft' check (status in ('draft','sent','accepted','rejected','expired')),
  valid_until date,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  project_id uuid references public.projects(id) on delete set null,
  invoice_number text not null unique,
  title text not null,
  items jsonb not null default '[]'::jsonb,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  tax numeric(14,2) not null default 0 check (tax >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  amount_paid numeric(14,2) not null default 0 check (amount_paid >= 0 and amount_paid <= total),
  currency text not null default 'PKR',
  status text not null default 'unpaid' check (status in ('unpaid','partially_paid','paid','overdue','cancelled')),
  due_date date,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'PKR',
  method text,
  transaction_reference text,
  paid_at timestamptz not null default now(),
  recorded_by uuid references public.profiles(id) on delete set null default auth.uid(),
  notes text
);

create table if not exists public.portfolio_projects (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  client_display_name text,
  industry text,
  description text,
  cover_image_url text,
  project_url text,
  is_featured boolean not null default false,
  is_published boolean not null default false,
  client_approval boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Industry and service catalogues used by the public website and CRM.
create table if not exists public.industry_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  icon text,
  is_active boolean not null default true,
  sort_order integer not null default 0
);
create table if not exists public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  icon text,
  is_active boolean not null default true,
  sort_order integer not null default 0
);

-- Useful indexes
create index if not exists businesses_status_category_idx on public.businesses(status,category);
create index if not exists businesses_area_idx on public.businesses(area);
create index if not exists providers_status_service_idx on public.service_providers(status,service);
create index if not exists clients_manager_status_idx on public.clients(manager_id,status);
create index if not exists projects_client_status_idx on public.projects(client_id,status);
create index if not exists project_members_user_idx on public.project_members(user_id);
create index if not exists tasks_assignee_status_idx on public.tasks(assigned_to,status);
create index if not exists tasks_due_date_idx on public.tasks(due_date);
create index if not exists leads_status_created_idx on public.leads(status,created_at desc);
create index if not exists notifications_recipient_read_idx on public.notifications(recipient_id,read_at);
create index if not exists reviews_business_status_idx on public.business_reviews(business_id,status);

-- Prevent team members from changing task ownership or task instructions.
create or replace function app_private.protect_member_task_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if app_private.current_role() = 'member' then
    if new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.client_id is distinct from old.client_id
      or new.project_id is distinct from old.project_id
      or new.assigned_to is distinct from old.assigned_to
      or new.created_by is distinct from old.created_by
      or new.priority is distinct from old.priority
      or new.due_date is distinct from old.due_date
      or new.estimated_hours is distinct from old.estimated_hours
      or new.deliverables is distinct from old.deliverables
      or new.completed_at is distinct from old.completed_at then
      raise exception 'Team members may update task progress only.';
    end if;
    if new.status not in ('in_progress','under_review','revision_required') then
      raise exception 'Team members may submit work for review but cannot approve or cancel tasks.';
    end if;
  end if;
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function app_private.protect_member_task_update() from public, anon, authenticated;
drop trigger if exists protect_member_task_update on public.tasks;
create trigger protect_member_task_update before update on public.tasks
for each row execute function app_private.protect_member_task_update();

-- Automatically maintain updated_at on mutable records.
create or replace function app_private.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;
revoke all on function app_private.set_updated_at() from public, anon, authenticated;
do $$
declare t text;
begin
  foreach t in array array['profiles','businesses','service_providers','clients','projects','tasks','portfolio_projects'] loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format('create trigger set_updated_at before update on public.%I for each row execute function app_private.set_updated_at()', t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- RLS: enable on every exposed application table.
-- -----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','team_directory','businesses','service_providers','business_submissions','provider_submissions',
    'business_reviews','clients','client_contacts','projects','project_members','tasks',
    'task_comments','task_attachments','activity_logs','notifications','leads',
    'quotations','invoices','payments','portfolio_projects','industry_catalog','service_catalog'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Revoke broad defaults, then grant only what the app needs.
revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;

-- Catalogues are public-readable; only the owner can manage them.
grant select on public.industry_catalog, public.service_catalog to anon, authenticated;
grant insert, update, delete on public.industry_catalog, public.service_catalog to authenticated;
create policy "Public reads active industries" on public.industry_catalog for select to anon, authenticated using (is_active = true);
create policy "Public reads active services" on public.service_catalog for select to anon, authenticated using (is_active = true);
create policy "Owner manages industries" on public.industry_catalog for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());
create policy "Owner manages service catalogue" on public.service_catalog for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());

-- Public reads for approved directory entries and published portfolio only.
grant select on public.businesses, public.service_providers, public.portfolio_projects, public.business_reviews to anon, authenticated;
create policy "Public can read approved businesses" on public.businesses for select to anon, authenticated using (status = 'approved');
create policy "Public can read approved providers" on public.service_providers for select to anon, authenticated using (status = 'approved');
create policy "Public can read published portfolio" on public.portfolio_projects for select to anon, authenticated using (is_published = true and client_approval = true);
create policy "Public can read approved reviews" on public.business_reviews for select to anon, authenticated using (status = 'approved');
create policy "Owner can read all reviews" on public.business_reviews for select to authenticated using (app_private.is_owner());

-- Public visitors can submit listing applications and enquiries. They cannot publish records.
grant insert on public.business_submissions, public.provider_submissions, public.leads to anon, authenticated;
create policy "Visitors can submit business listing requests" on public.business_submissions for insert to anon, authenticated with check (status = 'pending');
create policy "Visitors can submit provider requests" on public.provider_submissions for insert to anon, authenticated with check (status = 'pending');
create policy "Visitors can submit leads" on public.leads for insert to anon, authenticated with check (status = 'new' and assigned_to is null);

-- Profile access: members and managers see only their own full profile; owners can see all. Managers use the restricted team_directory.
grant select on public.profiles to authenticated;
grant update (full_name,job_title,avatar_url,skills,phone) on public.profiles to authenticated;
create policy "Users can view own profile and owner can view all" on public.profiles for select to authenticated using (id = (select auth.uid()) or app_private.is_owner());
grant select on public.team_directory to authenticated;
create policy "Owner and manager can view limited team directory" on public.team_directory for select to authenticated using (app_private.is_manager_or_owner());
create policy "Users can update own safe profile fields" on public.profiles for update to authenticated using (id = (select auth.uid()) or app_private.is_owner()) with check (id = (select auth.uid()) or app_private.is_owner());

-- Business administration is owner-only.
grant select, insert, update, delete on public.businesses, public.service_providers to authenticated;
create policy "Owner manages businesses" on public.businesses for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());
create policy "Owner manages service providers" on public.service_providers for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());
grant select, update on public.business_submissions, public.provider_submissions to authenticated;
create policy "Owner reviews business submissions" on public.business_submissions for select to authenticated using (app_private.is_owner());
create policy "Owner reviews provider submissions" on public.provider_submissions for select to authenticated using (app_private.is_owner());
create policy "Owner updates business submissions" on public.business_submissions for update to authenticated using (app_private.is_owner()) with check (app_private.is_owner());
create policy "Owner updates provider submissions" on public.provider_submissions for update to authenticated using (app_private.is_owner()) with check (app_private.is_owner());

grant insert on public.business_reviews to authenticated;
create policy "Signed in users can submit pending reviews" on public.business_reviews for insert to authenticated with check (user_id = (select auth.uid()) and status = 'pending');
create policy "Owner updates reviews" on public.business_reviews for update to authenticated using (app_private.is_owner()) with check (app_private.is_owner());
create policy "Owner deletes reviews" on public.business_reviews for delete to authenticated using (app_private.is_owner());

-- CRM records: manager and owner may coordinate client records and contact history.
grant select, insert, update, delete on public.clients, public.client_contacts to authenticated;
create policy "Owner and manager read clients" on public.clients for select to authenticated using (app_private.is_manager_or_owner());
create policy "Owner and manager create clients" on public.clients for insert to authenticated with check (app_private.is_manager_or_owner() and created_by=(select auth.uid()));
create policy "Owner and manager update clients" on public.clients for update to authenticated using (app_private.is_manager_or_owner()) with check (app_private.is_manager_or_owner());
create policy "Only owner deletes clients" on public.clients for delete to authenticated using (app_private.is_owner());
create policy "Owner and manager read client contacts" on public.client_contacts for select to authenticated using (app_private.is_manager_or_owner());
create policy "Owner and manager add client contacts" on public.client_contacts for insert to authenticated with check (app_private.is_manager_or_owner() and created_by=(select auth.uid()));
create policy "Owner and manager update client contacts" on public.client_contacts for update to authenticated using (app_private.is_manager_or_owner()) with check (app_private.is_manager_or_owner());
create policy "Only owner deletes client contacts" on public.client_contacts for delete to authenticated using (app_private.is_owner());

-- Projects: team members only see projects they are assigned to.
grant select, insert, update, delete on public.projects, public.project_members to authenticated;
create policy "Members read assigned projects" on public.projects for select to authenticated using (app_private.can_access_project(id));
create policy "Owner and manager create projects" on public.projects for insert to authenticated with check (app_private.is_manager_or_owner() and created_by=(select auth.uid()));
create policy "Owner and manager update projects" on public.projects for update to authenticated using (app_private.is_manager_or_owner()) with check (app_private.is_manager_or_owner());
create policy "Only owner deletes projects" on public.projects for delete to authenticated using (app_private.is_owner());
create policy "Members read own project assignments" on public.project_members for select to authenticated using (user_id=(select auth.uid()) or app_private.is_manager_or_owner());
create policy "Owner and manager manage project assignments" on public.project_members for all to authenticated using (app_private.is_manager_or_owner()) with check (app_private.is_manager_or_owner());

-- Tasks: owner/manager assign and supervise; members read/update only their own assigned task progress.
grant select, insert, update, delete on public.tasks to authenticated;
create policy "Owner manager or assignee read tasks" on public.tasks for select to authenticated using (app_private.is_manager_or_owner() or assigned_to=(select auth.uid()) or (project_id is not null and app_private.can_access_project(project_id)));
create policy "Owner and manager create tasks" on public.tasks for insert to authenticated with check (app_private.is_manager_or_owner() and created_by=(select auth.uid()));
create policy "Owner manager or assignee update tasks" on public.tasks for update to authenticated using (app_private.is_manager_or_owner() or assigned_to=(select auth.uid())) with check (app_private.is_manager_or_owner() or assigned_to=(select auth.uid()));
create policy "Only owner and manager delete tasks" on public.tasks for delete to authenticated using (app_private.is_manager_or_owner());

grant select, insert on public.task_comments, public.task_attachments to authenticated;
create policy "Users read comments for tasks they can see" on public.task_comments for select to authenticated using (exists(select 1 from public.tasks t where t.id=task_id));
create policy "Assigned members and managers add task comments" on public.task_comments for insert to authenticated with check (author_id=(select auth.uid()) and exists(select 1 from public.tasks t where t.id=task_id and (app_private.is_manager_or_owner() or t.assigned_to=(select auth.uid()) or (t.project_id is not null and app_private.can_access_project(t.project_id)))));
create policy "Users read attachments for tasks they can see" on public.task_attachments for select to authenticated using (exists(select 1 from public.tasks t where t.id=task_id));
create policy "Assigned members and managers add attachments" on public.task_attachments for insert to authenticated with check (uploaded_by=(select auth.uid()) and exists(select 1 from public.tasks t where t.id=task_id and (app_private.is_manager_or_owner() or t.assigned_to=(select auth.uid()) or (t.project_id is not null and app_private.can_access_project(t.project_id)))));

-- Internal audit and notifications.
grant select, insert on public.activity_logs to authenticated;
create policy "Owner reads activity log" on public.activity_logs for select to authenticated using (app_private.is_owner());
create policy "Authenticated user records own activity" on public.activity_logs for insert to authenticated with check (actor_id=(select auth.uid()) and app_private.is_manager_or_owner());
grant select, update on public.notifications to authenticated;
create policy "Users read own notifications" on public.notifications for select to authenticated using (recipient_id=(select auth.uid()) or app_private.is_owner());
create policy "Users update own notifications" on public.notifications for update to authenticated using (recipient_id=(select auth.uid())) with check (recipient_id=(select auth.uid()));

-- Leads: managers handle client communication; owner controls all CRM leads.
grant select, update, delete on public.leads to authenticated;
create policy "Owner and manager read leads" on public.leads for select to authenticated using (app_private.is_manager_or_owner());
create policy "Owner and manager update leads" on public.leads for update to authenticated using (app_private.is_manager_or_owner()) with check (app_private.is_manager_or_owner());
create policy "Only owner deletes leads" on public.leads for delete to authenticated using (app_private.is_owner());

-- Financial records are owner-only.
grant select, insert, update, delete on public.quotations, public.invoices, public.payments to authenticated;
create policy "Owner only quotations" on public.quotations for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());
create policy "Owner only invoices" on public.invoices for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());
create policy "Owner only payments" on public.payments for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());

-- Portfolio: public only sees published work with documented client permission.
grant select, insert, update, delete on public.portfolio_projects to authenticated;
create policy "Owner manages portfolio" on public.portfolio_projects for all to authenticated using (app_private.is_owner()) with check (app_private.is_owner());

-- Sequences are not needed for UUID-backed tables, but grant schema access explicitly.
grant usage on schema public to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Storage buckets and policies. Avatar images are public; work documents are private.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values
  ('team-avatars','team-avatars',true,5242880,array['image/jpeg','image/png','image/webp']),
  ('private-work-files','private-work-files',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','application/zip'])
on conflict (id) do nothing;

create policy "Public can view team avatars" on storage.objects for select to anon, authenticated using (bucket_id='team-avatars');
create policy "Users upload own avatar folder" on storage.objects for insert to authenticated with check (bucket_id='team-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Users update own avatar folder" on storage.objects for update to authenticated using (bucket_id='team-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text) with check (bucket_id='team-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Owners manage all team avatars" on storage.objects for all to authenticated using (bucket_id='team-avatars' and app_private.is_owner()) with check (bucket_id='team-avatars' and app_private.is_owner());
create policy "Users access own work files and managers access team files" on storage.objects for select to authenticated using (bucket_id='private-work-files' and ((storage.foldername(name))[1]=(select auth.uid())::text or app_private.is_manager_or_owner()));
create policy "Users upload own work files" on storage.objects for insert to authenticated with check (bucket_id='private-work-files' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Users update own work files" on storage.objects for update to authenticated using (bucket_id='private-work-files' and (storage.foldername(name))[1]=(select auth.uid())::text) with check (bucket_id='private-work-files' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Owners manage private work files" on storage.objects for all to authenticated using (bucket_id='private-work-files' and app_private.is_owner()) with check (bucket_id='private-work-files' and app_private.is_owner());

-- End of schema. Verify RLS and policies in Supabase before inviting real staff.
