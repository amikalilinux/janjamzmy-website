create extension if not exists "pgcrypto";

do $$ begin
  create type public.profile_role as enum ('owner', 'manager', 'team_member');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.profile_status as enum ('active', 'suspended');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.client_status as enum (
    'new_lead', 'contacted', 'meeting_scheduled', 'proposal_sent',
    'negotiation', 'active', 'completed', 'inactive'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.contact_type as enum ('call', 'meeting', 'email', 'whatsapp', 'note');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.project_status as enum (
    'planning', 'design', 'development', 'testing', 'client_review',
    'revision', 'delivered'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.task_priority as enum ('urgent', 'high', 'medium', 'low');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.task_status as enum (
    'not_started', 'assigned', 'in_progress', 'under_review',
    'revision_required', 'completed', 'cancelled'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.lead_source as enum ('contact_form', 'quote_request', 'whatsapp');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.invoice_status as enum ('unpaid', 'partial', 'paid', 'overdue', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.business_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on update cascade on delete cascade,
  role public.profile_role not null default 'team_member',
  name text not null,
  position text,
  phone text,
  skills text[] not null default '{}'::text[],
  photo_url text,
  status public.profile_status not null default 'active',
  mfa_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_name_not_blank check (length(btrim(name)) > 0)
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  category text,
  contact_person text,
  phone text,
  whatsapp text,
  email text,
  address text,
  city_area text,
  website text,
  social_media jsonb not null default '{}'::jsonb,
  requirements text,
  assigned_manager_id uuid references public.profiles(id) on update cascade on delete set null,
  notes text,
  status public.client_status not null default 'new_lead',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_business_name_not_blank check (length(btrim(business_name)) > 0),
  constraint clients_email_format check (email is null or email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
);

create table public.client_contacts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on update cascade on delete cascade,
  contact_date timestamptz not null default now(),
  type public.contact_type not null,
  summary text not null,
  follow_up_date timestamptz,
  created_by uuid references public.profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_contacts_summary_not_blank check (length(btrim(summary)) > 0),
  constraint client_contacts_follow_up_after_contact check (follow_up_date is null or follow_up_date >= contact_date)
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on update cascade on delete restrict,
  name text not null,
  description text,
  manager_id uuid references public.profiles(id) on update cascade on delete set null,
  budget_pkr bigint not null default 0,
  start_date date,
  deadline date,
  status public.project_status not null default 'planning',
  progress_percent integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint projects_name_not_blank check (length(btrim(name)) > 0),
  constraint projects_budget_nonnegative check (budget_pkr >= 0),
  constraint projects_progress_range check (progress_percent between 0 and 100),
  constraint projects_dates_valid check (start_date is null or deadline is null or deadline >= start_date)
);

create table public.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on update cascade on delete cascade,
  member_id uuid not null references public.profiles(id) on update cascade on delete cascade,
  role_in_project text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_members_unique unique (project_id, member_id)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on update cascade on delete set null,
  client_id uuid references public.clients(id) on update cascade on delete set null,
  title text not null,
  description text,
  assignee_id uuid references public.profiles(id) on update cascade on delete set null,
  manager_id uuid references public.profiles(id) on update cascade on delete set null,
  creator_id uuid references public.profiles(id) on update cascade on delete set null,
  priority public.task_priority not null default 'medium',
  status public.task_status not null default 'not_started',
  start_date date,
  deadline timestamptz,
  estimated_hours numeric(8,2),
  task_type text,
  deliverables text,
  instructions text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tasks_title_not_blank check (length(btrim(title)) > 0),
  constraint tasks_estimated_hours_nonnegative check (estimated_hours is null or estimated_hours >= 0),
  constraint tasks_completed_at_valid check (
    (status = 'completed' and completed_at is not null)
    or (status <> 'completed')
  )
);

create table public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on update cascade on delete cascade,
  user_id uuid not null references public.profiles(id) on update cascade on delete cascade,
  body text not null,
  is_internal boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint task_comments_body_not_blank check (length(btrim(body)) > 0)
);

create table public.task_attachments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on update cascade on delete cascade,
  file_path text not null,
  file_name text not null,
  uploaded_by uuid references public.profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint task_attachments_path_not_blank check (length(btrim(file_path)) > 0),
  constraint task_attachments_name_not_blank check (length(btrim(file_name)) > 0)
);

create table public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on update cascade on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activity_logs_action_not_blank check (length(btrim(action)) > 0),
  constraint activity_logs_entity_type_not_blank check (length(btrim(entity_type)) > 0)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on update cascade on delete cascade,
  type text not null,
  title text not null,
  body text,
  link_url text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notifications_type_not_blank check (length(btrim(type)) > 0),
  constraint notifications_title_not_blank check (length(btrim(title)) > 0)
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  source public.lead_source not null,
  name text not null,
  phone text,
  email text,
  business_name text,
  message text not null,
  status text not null default 'new',
  assigned_to uuid references public.profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leads_name_not_blank check (length(btrim(name)) > 0),
  constraint leads_message_not_blank check (length(btrim(message)) > 0),
  constraint leads_status_check check (status in ('new','contacted','qualified','converted','closed'))
);

create table public.quotations (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on update cascade on delete restrict,
  project_id uuid references public.projects(id) on update cascade on delete set null,
  quote_number text not null,
  items_json jsonb not null default '[]'::jsonb,
  total_pkr bigint not null default 0,
  valid_until date,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotations_number_not_blank check (length(btrim(quote_number)) > 0),
  constraint quotations_total_nonnegative check (total_pkr >= 0),
  constraint quotations_status_check check (status in ('draft','sent','accepted','rejected','expired')),
  constraint quotations_number_unique unique (quote_number)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on update cascade on delete restrict,
  project_id uuid references public.projects(id) on update cascade on delete set null,
  invoice_number text not null,
  items_json jsonb not null default '[]'::jsonb,
  subtotal_pkr bigint not null default 0,
  tax_pkr bigint not null default 0,
  total_pkr bigint not null default 0,
  due_date date,
  status public.invoice_status not null default 'unpaid',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoices_number_not_blank check (length(btrim(invoice_number)) > 0),
  constraint invoices_amounts_nonnegative check (subtotal_pkr >= 0 and tax_pkr >= 0 and total_pkr >= 0),
  constraint invoices_number_unique unique (invoice_number)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on update cascade on delete restrict,
  amount_pkr bigint not null,
  method text not null,
  transaction_ref text,
  paid_at timestamptz not null default now(),
  recorded_by uuid references public.profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_amount_positive check (amount_pkr > 0),
  constraint payments_method_not_blank check (length(btrim(method)) > 0)
);

create table public.portfolio_projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on update cascade on delete set null,
  project_id uuid references public.projects(id) on update cascade on delete set null,
  title text not null,
  description text,
  cover_image_url text,
  screenshots text[] not null default '{}'::text[],
  external_url text,
  industry text,
  is_featured boolean,
  is_published boolean not null default false,
  approved_by uuid references public.profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint portfolio_projects_title_not_blank check (length(btrim(title)) > 0)
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text,
  address text,
  phone text,
  whatsapp text,
  rating numeric(2,1),
  hours text,
  latitude double precision,
  longitude double precision,
  status public.business_status not null default 'pending',
  submitted_by uuid references auth.users(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint businesses_name_not_blank check (length(btrim(name)) > 0),
  constraint businesses_rating_range check (rating is null or rating between 0 and 5),
  constraint businesses_latitude_range check (latitude is null or latitude between -90 and 90),
  constraint businesses_longitude_range check (longitude is null or longitude between -180 and 180)
);

create table public.service_providers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  service_type text not null,
  phone text,
  address text,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_providers_name_not_blank check (length(btrim(name)) > 0),
  constraint service_providers_type_not_blank check (length(btrim(service_type)) > 0)
);

create table public.business_reviews (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on update cascade on delete cascade,
  reviewer_name text not null,
  rating integer not null,
  comment text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_reviews_reviewer_not_blank check (length(btrim(reviewer_name)) > 0),
  constraint business_reviews_rating_range check (rating between 1 and 5),
  constraint business_reviews_status_check check (status in ('pending','approved','rejected'))
);

create index profiles_role_status_idx on public.profiles(role, status);
create index clients_manager_status_idx on public.clients(assigned_manager_id, status);
create index client_contacts_client_date_idx on public.client_contacts(client_id, contact_date desc);
create index projects_client_status_idx on public.projects(client_id, status);
create index project_members_member_idx on public.project_members(member_id);
create index tasks_assignee_status_idx on public.tasks(assignee_id, status);
create index tasks_manager_status_idx on public.tasks(manager_id, status);
create index tasks_project_idx on public.tasks(project_id);
create index tasks_deadline_idx on public.tasks(deadline);
create index task_comments_task_idx on public.task_comments(task_id, created_at desc);
create index task_attachments_task_idx on public.task_attachments(task_id);
create index activity_logs_actor_idx on public.activity_logs(actor_id, created_at desc);
create index activity_logs_entity_idx on public.activity_logs(entity_type, entity_id);
create index notifications_user_unread_idx on public.notifications(user_id, read_at, created_at desc);
create index leads_status_assigned_idx on public.leads(status, assigned_to);
create index quotations_client_idx on public.quotations(client_id);
create index invoices_client_status_idx on public.invoices(client_id, status);
create index payments_invoice_idx on public.payments(invoice_id);
create index portfolio_featured_published_idx on public.portfolio_projects(is_featured, is_published);
create index businesses_status_category_idx on public.businesses(status, category);
create index service_providers_type_verified_idx on public.service_providers(service_type, verified);
create index business_reviews_business_status_idx on public.business_reviews(business_id, status);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'profiles','clients','client_contacts','projects','project_members','tasks',
    'task_comments','task_attachments','activity_logs','notifications','leads',
    'quotations','invoices','payments','portfolio_projects','businesses',
    'service_providers','business_reviews'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create trigger set_%I_updated_at before update on public.%I
       for each row execute function public.set_updated_at()',
      table_name, table_name
    );
  end loop;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    'team_member'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select exists (
  select 1 from public.profiles
  where id = auth.uid() and role = 'owner'
) $$;

create or replace function public.is_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select exists (
  select 1 from public.profiles
  where id = auth.uid() and role = 'manager'
) $$;

create or replace function public.is_owner_or_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select public.is_owner() or public.is_manager() $$;

create or replace function public.manager_assigned_to_client(client_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select exists (
  select 1 from public.clients
  where id = client_uuid
    and assigned_manager_id = auth.uid()
    and exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'manager'
    )
) $$;

-- profiles
create policy "profiles_select_owner" on public.profiles
for select to authenticated using (public.is_owner());

create policy "profiles_select_self" on public.profiles
for select to authenticated using (id = auth.uid());

create policy "profiles_select_manager_team" on public.profiles
for select to authenticated using (
  public.is_manager() and role = 'team_member'
);

create policy "profiles_update_owner" on public.profiles
for update to authenticated
using (public.is_owner())
with check (public.is_owner());

create policy "profiles_update_self" on public.profiles
for update to authenticated
using (id = auth.uid())
with check (
  id = auth.uid()
  and role = (select p.role from public.profiles p where p.id = auth.uid())
);

-- clients
create policy "clients_owner_all" on public.clients
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "clients_manager_assigned_all" on public.clients
for all to authenticated
using (public.is_manager() and assigned_manager_id = auth.uid())
with check (public.is_manager() and assigned_manager_id = auth.uid());

-- client contacts
create policy "client_contacts_owner_all" on public.client_contacts
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "client_contacts_manager_assigned_all" on public.client_contacts
for all to authenticated
using (public.is_manager() and public.manager_assigned_to_client(client_id))
with check (public.is_manager() and public.manager_assigned_to_client(client_id));

-- projects
create policy "projects_owner_all" on public.projects
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "projects_manager_assigned_all" on public.projects
for all to authenticated
using (public.is_manager() and public.manager_assigned_to_client(client_id))
with check (public.is_manager() and public.manager_assigned_to_client(client_id));

-- project members
create policy "project_members_owner_all" on public.project_members
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "project_members_manager_assigned" on public.project_members
for all to authenticated
using (
  public.is_manager()
  and exists (
    select 1 from public.projects p
    where p.id = project_id
      and public.manager_assigned_to_client(p.client_id)
  )
)
with check (
  public.is_manager()
  and exists (
    select 1 from public.projects p
    where p.id = project_id
      and public.manager_assigned_to_client(p.client_id)
  )
);

-- tasks
create policy "tasks_owner_select" on public.tasks
for select to authenticated using (public.is_owner());

create policy "tasks_manager_select" on public.tasks
for select to authenticated using (
  public.is_manager()
  and (manager_id = auth.uid() or assignee_id = auth.uid())
);

create policy "tasks_team_select" on public.tasks
for select to authenticated using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'team_member'
  )
  and assignee_id = auth.uid()
);

create policy "tasks_owner_manager_insert" on public.tasks
for insert to authenticated
with check (public.is_owner_or_manager());

create policy "tasks_owner_manager_update" on public.tasks
for update to authenticated
using (public.is_owner_or_manager())
with check (public.is_owner_or_manager());

create policy "tasks_team_update_own" on public.tasks
for update to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'team_member'
  )
  and assignee_id = auth.uid()
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'team_member'
  )
  and assignee_id = auth.uid()
);

create or replace function public.protect_team_task_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_team_member boolean;
begin
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'team_member'
  ) into is_team_member;

  if is_team_member and (
    old.project_id is distinct from new.project_id
    or old.client_id is distinct from new.client_id
    or old.title is distinct from new.title
    or old.description is distinct from new.description
    or old.assignee_id is distinct from new.assignee_id
    or old.manager_id is distinct from new.manager_id
    or old.creator_id is distinct from new.creator_id
    or old.priority is distinct from new.priority
    or old.start_date is distinct from new.start_date
    or old.deadline is distinct from new.deadline
    or old.estimated_hours is distinct from new.estimated_hours
    or old.task_type is distinct from new.task_type
    or old.deliverables is distinct from new.deliverables
    or old.instructions is distinct from new.instructions
  ) then
    raise exception 'Team members may only update status and completed_at';
  end;
  return new;
end;
$$;

drop trigger if exists protect_team_task_columns on public.tasks;
create trigger protect_team_task_columns
before update on public.tasks
for each row execute function public.protect_team_task_columns();

-- task comments and attachments
create policy "task_comments_owner_all" on public.task_comments
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "task_comments_assigned_or_manager" on public.task_comments
for all to authenticated
using (
  exists (
    select 1 from public.tasks t
    where t.id = task_id
      and (t.assignee_id = auth.uid() or t.manager_id = auth.uid())
  )
)
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.tasks t
    where t.id = task_id
      and (t.assignee_id = auth.uid() or t.manager_id = auth.uid())
  )
);

create policy "task_attachments_owner_all" on public.task_attachments
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "task_attachments_assigned_manager_read_insert" on public.task_attachments
for all to authenticated
using (
  exists (
    select 1 from public.tasks t
    where t.id = task_id
      and (t.assignee_id = auth.uid() or t.manager_id = auth.uid())
  )
)
with check (
  uploaded_by = auth.uid()
  and exists (
    select 1 from public.tasks t
    where t.id = task_id
      and (t.assignee_id = auth.uid() or t.manager_id = auth.uid())
  )
);

-- activity logs
create policy "activity_logs_owner_all" on public.activity_logs
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "activity_logs_manager_insert" on public.activity_logs
for insert to authenticated
with check (public.is_manager() and actor_id = auth.uid());

-- notifications
create policy "notifications_select_own" on public.notifications
for select to authenticated using (user_id = auth.uid());

create policy "notifications_update_own" on public.notifications
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "notifications_owner_insert" on public.notifications
for insert to authenticated
with check (public.is_owner());

create policy "notifications_manager_insert" on public.notifications
for insert to authenticated
with check (public.is_manager());

-- leads
create policy "leads_anon_insert" on public.leads
for insert to anon
with check (true);

create policy "leads_owner_all" on public.leads
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "leads_manager_all" on public.leads
for all to authenticated
using (public.is_manager())
with check (public.is_manager());

-- quotations
create policy "quotations_owner_all" on public.quotations
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "quotations_manager_assigned_all" on public.quotations
for all to authenticated
using (public.is_manager() and public.manager_assigned_to_client(client_id))
with check (public.is_manager() and public.manager_assigned_to_client(client_id));

-- invoices
create policy "invoices_owner_all" on public.invoices
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "invoices_manager_assigned_all" on public.invoices
for all to authenticated
using (public.is_manager() and public.manager_assigned_to_client(client_id))
with check (public.is_manager() and public.manager_assigned_to_client(client_id));

-- payments
create policy "payments_owner_all" on public.payments
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "payments_manager_assigned_all" on public.payments
for all to authenticated
using (
  public.is_manager()
  and exists (
    select 1
    from public.invoices i
    where i.id = invoice_id
      and public.manager_assigned_to_client(i.client_id)
  )
)
with check (
  public.is_manager()
  and exists (
    select 1
    from public.invoices i
    where i.id = invoice_id
      and public.manager_assigned_to_client(i.client_id)
  )
);

-- public portfolio
create policy "portfolio_anon_published_featured_select" on public.portfolio_projects
for select to anon
using (is_published = true and is_featured is not null);

create policy "portfolio_authenticated_owner_all" on public.portfolio_projects
for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy "portfolio_authenticated_featured_select" on public.portfolio_projects
for select to authenticated
using (is_published = true and is_featured is not null);

-- businesses public directory
create policy "businesses_anon_approved_select" on public.businesses
for select to anon using (status = 'approved');

create policy "businesses_anon_pending_insert" on public.businesses
for insert to anon
with check (status = 'pending');

create policy "businesses_authenticated_approved_select" on public.businesses
for select to authenticated using (status = 'approved');

create policy "businesses_owner_all" on public.businesses
for all to authenticated using (public.is_owner()) with check (public.is_owner());

-- service providers
create policy "service_providers_anon_verified_select" on public.service_providers
for select to anon using (verified = true);

create policy "service_providers_owner_all" on public.service_providers
for all to authenticated using (public.is_owner()) with check (public.is_owner());

-- business reviews
create policy "business_reviews_anon_approved_select" on public.business_reviews
for select to anon using (status = 'approved');

create policy "business_reviews_anon_pending_insert" on public.business_reviews
for insert to anon
with check (status = 'pending');

create policy "business_reviews_owner_all" on public.business_reviews
for all to authenticated using (public.is_owner()) with check (public.is_owner());

insert into storage.buckets (id, name, public)
values
  ('member-photos', 'member-photos', false),
  ('task-attachments', 'task-attachments', false)
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public;

create policy "member_photos_owner_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'member-photos'
  and public.is_owner()
);

create policy "member_photos_authenticated_select"
on storage.objects for select to authenticated
using (bucket_id = 'member-photos');

create policy "task_attachments_owner_manager_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'task-attachments'
  and public.is_owner_or_manager()
);

create policy "task_attachments_assigned_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'task-attachments'
  and exists (
    select 1
    from public.tasks t
    where t.assignee_id = auth.uid()
      and (storage.foldername(name))[1] = t.id::text
  )
);

create policy "task_attachments_owner_manager_select"
on storage.objects for select to authenticated
using (
  bucket_id = 'task-attachments'
  and public.is_owner_or_manager()
);

create policy "task_attachments_assigned_select"
on storage.objects for select to authenticated
using (
  bucket_id = 'task-attachments'
  and exists (
    select 1
    from public.tasks t
    where t.assignee_id = auth.uid()
      and (storage.foldername(name))[1] = t.id::text
  )
);
