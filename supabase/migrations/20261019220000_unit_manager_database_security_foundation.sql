-- NCC Unit Manager: additive database and security foundation.
-- Existing NTS tables are deliberately left untouched. The um_ prefix isolates
-- this specification from the legacy NTS schema, which has incompatible models/roles.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

do $$ begin
  create type public.um_role as enum ('admin','officer','senior','cadet');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.um_parade_type as enum ('DRILL','PT','WEAPON_TRAINING','CAMP_PREP','OTHER');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.um_parade_status as enum ('DRAFT','PROPOSED','APPROVED','COMPLETED','CANCELLED');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.um_attendance_status as enum ('PRESENT','ABSENT','LATE','LEAVE');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.um_leave_status as enum ('PENDING','APPROVED','REJECTED','CANCELLED');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.um_inventory_condition as enum ('SERVICEABLE','NEEDS_REPAIR','DAMAGED','LOST');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.um_issue_status as enum ('REQUESTED','ISSUED','RETURNED','REJECTED');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.um_certificate_level as enum ('A','B','C');
exception when duplicate_object then null; end $$;

create table if not exists public.um_units (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null,
  timezone text not null default 'Asia/Kolkata',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(code)
);

create table if not exists public.um_flights (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  code text not null,
  name text not null,
  description text not null default '',
  flight_senior_profile_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(unit_id, code),
  unique(unit_id, name),
  unique(unit_id, id)
);

create table if not exists public.um_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  unit_id uuid not null references public.um_units(id) on delete restrict,
  flight_id uuid,
  full_name text not null,
  email text,
  phone text,
  force_password_change boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, unit_id),
  foreign key (unit_id, flight_id) references public.um_flights(unit_id, id) deferrable initially deferred
);

alter table public.um_flights
  drop constraint if exists um_flights_senior_profile_fk;
alter table public.um_flights
  add constraint um_flights_senior_profile_fk
  foreign key (flight_senior_profile_id) references public.um_profiles(id) on delete set null;

create table if not exists public.um_user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  unit_id uuid not null references public.um_units(id) on delete restrict,
  role public.um_role not null,
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(user_id, unit_id)
);

create table if not exists public.um_cadets (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  flight_id uuid,
  regimental_no text not null,
  full_name text not null,
  wing text not null default 'AIR',
  year_of_training smallint not null check (year_of_training between 1 and 3),
  rank text not null default 'Cadet',
  date_of_birth date,
  phone text,
  guardian_name text,
  guardian_phone text,
  guardian_consent boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','TRANSFERRED','DISCHARGED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(unit_id, regimental_no),
  unique(unit_id, id),
  unique(user_id),
  foreign key (unit_id, flight_id) references public.um_flights(unit_id, id) deferrable initially deferred
);

create table if not exists public.um_parade_series (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  title text not null,
  parade_type public.um_parade_type not null,
  venue text not null,
  description text not null default '',
  weekday smallint not null check (weekday between 0 and 6),
  start_date date not null,
  end_date date not null,
  start_time time not null,
  end_time time not null,
  target_flights uuid[] not null default '{}',
  target_years smallint[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (end_date >= start_date),
  check (end_time > start_time),
  check (target_years <@ array[1,2,3]::smallint[])
);

create table if not exists public.um_parades (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  series_id uuid references public.um_parade_series(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  title text not null,
  parade_date date not null,
  starts_at time not null,
  ends_at time not null,
  venue text not null,
  parade_type public.um_parade_type not null,
  description text not null default '',
  status public.um_parade_status not null default 'DRAFT',
  target_flights uuid[] not null default '{}',
  target_years smallint[] not null default '{}',
  cancel_reason text,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (status <> 'CANCELLED' or nullif(btrim(cancel_reason), '') is not null),
  check (target_years <@ array[1,2,3]::smallint[]),
  unique(unit_id, id)
);

create table if not exists public.um_holidays (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  holiday_date date not null,
  name text not null,
  notes text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(unit_id, holiday_date)
);

create table if not exists public.um_leave_requests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  cadet_id uuid not null references public.um_cadets(id) on delete cascade,
  starts_on date not null,
  ends_on date not null,
  reason text not null,
  status public.um_leave_status not null default 'PENDING',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table if not exists public.um_attendance (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  parade_id uuid not null references public.um_parades(id) on delete cascade,
  cadet_id uuid not null references public.um_cadets(id) on delete cascade,
  status public.um_attendance_status not null,
  notes text not null default '',
  marked_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(parade_id, cadet_id)
);

create table if not exists public.um_inventory_items (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  item_code text not null,
  name text not null,
  description text not null default '',
  total_qty integer not null default 0 check (total_qty >= 0),
  condition public.um_inventory_condition not null default 'SERVICEABLE',
  reorder_level integer not null default 0 check (reorder_level >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(unit_id, item_code),
  unique(unit_id, id)
);

create table if not exists public.um_inventory_issues (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  item_id uuid not null references public.um_inventory_items(id) on delete restrict,
  cadet_id uuid not null references public.um_cadets(id) on delete restrict,
  qty integer not null check (qty > 0),
  due_date date,
  status public.um_issue_status not null default 'REQUESTED',
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz,
  returned_at timestamptz,
  condition_on_return public.um_inventory_condition,
  return_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.um_stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  item_id uuid not null references public.um_inventory_items(id) on delete restrict,
  quantity_delta integer not null check (quantity_delta <> 0),
  reason text not null,
  adjusted_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.um_fitness_metrics (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  code text not null,
  name text not null,
  unit_label text not null default '',
  higher_is_better boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(unit_id, code),
  unique(unit_id, id)
);

create table if not exists public.um_fitness_standards (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  metric_id uuid not null references public.um_fitness_metrics(id) on delete cascade,
  gender text not null check (gender in ('FEMALE','MALE','UNSPECIFIED')),
  age_min smallint not null check (age_min >= 0),
  age_max smallint not null check (age_max >= age_min),
  minimum_pass numeric not null,
  excellent numeric not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(unit_id, metric_id, gender, age_min, age_max)
);

create table if not exists public.um_fitness_tests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  test_date date not null,
  title text not null,
  metric_id uuid not null references public.um_fitness_metrics(id) on delete restrict,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  notes text not null default '',
  created_at timestamptz not null default now(),
  unique(unit_id, id)
);

create table if not exists public.um_fitness_results (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  test_id uuid not null references public.um_fitness_tests(id) on delete cascade,
  cadet_id uuid not null references public.um_cadets(id) on delete cascade,
  result_value numeric not null,
  result_status text not null default 'RECORDED' check (result_status in ('BELOW_STANDARD','PASS','EXCELLENT','RECORDED')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(test_id, cadet_id)
);

create table if not exists public.um_syllabus_items (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  certificate_level public.um_certificate_level not null,
  subject text not null,
  topic text not null,
  sequence_no integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(unit_id, certificate_level, subject, topic),
  unique(unit_id, id)
);

create table if not exists public.um_cadet_syllabus_progress (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  cadet_id uuid not null references public.um_cadets(id) on delete cascade,
  syllabus_item_id uuid not null references public.um_syllabus_items(id) on delete cascade,
  completed_on date,
  signed_off_by uuid references auth.users(id) on delete set null,
  signed_off_at timestamptz,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(cadet_id, syllabus_item_id)
);

create table if not exists public.um_exam_results (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  cadet_id uuid not null references public.um_cadets(id) on delete cascade,
  certificate_level public.um_certificate_level not null,
  exam_date date,
  result text not null,
  marks numeric,
  notes text not null default '',
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.um_certificates (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  cadet_id uuid not null references public.um_cadets(id) on delete restrict,
  certificate_level public.um_certificate_level not null,
  certificate_number text not null,
  issued_on date not null,
  issued_by uuid not null references auth.users(id) on delete restrict,
  notes text not null default '',
  created_at timestamptz not null default now(),
  unique(unit_id, certificate_number),
  unique(cadet_id, certificate_level)
);

create table if not exists public.um_camps (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  name text not null,
  camp_type text not null,
  venue text not null,
  starts_on date not null,
  ends_on date not null,
  description text not null default '',
  status text not null default 'PLANNED' check (status in ('PLANNED','APPROVED','ONGOING','COMPLETED','CANCELLED')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table if not exists public.um_notifications (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete restrict,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null,
  notification_type text not null default 'INFO',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.um_settings (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.um_units(id) on delete cascade,
  attendance_threshold numeric not null default 75 check (attendance_threshold between 0 and 100),
  leave_counts_as_present boolean not null default true,
  flight_label text not null default 'Flight',
  settings jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(unit_id)
);

create table if not exists public.um_audit_log (
  id bigint generated always as identity primary key,
  unit_id uuid references public.um_units(id) on delete set null,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  table_name text not null,
  record_id text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists um_profiles_user_unit_idx on public.um_profiles(user_id, unit_id);
create index if not exists um_cadets_unit_flight_idx on public.um_cadets(unit_id, flight_id);
create index if not exists um_cadets_unit_name_idx on public.um_cadets(unit_id, full_name);
create index if not exists um_parades_unit_date_idx on public.um_parades(unit_id, parade_date);
create index if not exists um_attendance_unit_cadet_idx on public.um_attendance(unit_id, cadet_id);
create index if not exists um_leave_unit_status_idx on public.um_leave_requests(unit_id, status);
create index if not exists um_inventory_issues_due_idx on public.um_inventory_issues(unit_id, due_date) where returned_at is null;
create index if not exists um_notifications_recipient_idx on public.um_notifications(recipient_id, created_at desc);
create index if not exists um_audit_log_unit_created_idx on public.um_audit_log(unit_id, created_at desc);

create or replace function private.has_role(p_uid uuid, p_role public.um_role)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_uid is not null
     and p_uid = auth.uid()
     and exists (
       select 1 from public.um_user_roles r
       where r.user_id = p_uid and r.role = p_role
     );
$$;

create or replace function private.um_has_role_in_unit(p_uid uuid, p_unit_id uuid, p_role public.um_role)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_uid is not null
     and p_uid = auth.uid()
     and exists (
       select 1 from public.um_user_roles r
       where r.user_id = p_uid and r.unit_id = p_unit_id and r.role = p_role
     );
$$;

create or replace function private.um_member_of_unit(p_uid uuid, p_unit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_uid is not null
     and p_uid = auth.uid()
     and exists (
       select 1 from public.um_user_roles r
       where r.user_id = p_uid and r.unit_id = p_unit_id
     );
$$;

create or replace function private.current_unit_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case when count(*) = 1 then (array_agg(r.unit_id))[1] else null end
  from public.um_user_roles r
  where r.user_id = auth.uid();
$$;

create or replace function private.current_flight_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p.flight_id
  from public.um_profiles p
  where p.user_id = auth.uid()
    and p.unit_id = private.current_unit_id()
    and p.is_active
  limit 1;
$$;

create or replace function private.current_cadet_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select c.id
  from public.um_cadets c
  where c.user_id = auth.uid()
    and c.unit_id = private.current_unit_id()
    and c.status = 'ACTIVE'
  limit 1;
$$;

create or replace function private.um_can_read_cadet(p_uid uuid, p_unit_id uuid, p_cadet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_uid is not null and p_uid = auth.uid() and exists (
    select 1
    from public.um_cadets c
    where c.id = p_cadet_id
      and c.unit_id = p_unit_id
      and (
        c.user_id = p_uid
        or private.um_has_role_in_unit(p_uid, p_unit_id, 'admin')
        or private.um_has_role_in_unit(p_uid, p_unit_id, 'officer')
        or (
          private.um_has_role_in_unit(p_uid, p_unit_id, 'senior')
          and c.flight_id = private.current_flight_id()
        )
      )
  );
$$;

create or replace function private.um_audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_unit_id uuid;
  v_record_id text;
begin
  if tg_op = 'INSERT' then
    v_after := to_jsonb(new);
    v_unit_id := nullif(v_after ->> 'unit_id', '')::uuid;
    v_record_id := coalesce(v_after ->> 'id', v_after ->> 'regimental_no');
  elsif tg_op = 'UPDATE' then
    v_before := to_jsonb(old);
    v_after := to_jsonb(new);
    v_unit_id := coalesce(nullif(v_after ->> 'unit_id', '')::uuid, nullif(v_before ->> 'unit_id', '')::uuid);
    v_record_id := coalesce(v_after ->> 'id', v_before ->> 'id');
  else
    v_before := to_jsonb(old);
    v_unit_id := nullif(v_before ->> 'unit_id', '')::uuid;
    v_record_id := v_before ->> 'id';
  end if;

  insert into public.um_audit_log(unit_id, actor_id, action, table_name, record_id, before_data, after_data)
  values (
    v_unit_id,
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    v_record_id,
    case when v_before is null then null else v_before - 'created_at' - 'updated_at' end,
    case when v_after is null then null else v_after - 'created_at' - 'updated_at' end
  );

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create or replace function private.um_set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.um_enforce_parade_transition()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_officer boolean;
  v_is_admin boolean;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'DRAFT' then
      raise exception 'New parades must start in DRAFT status' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.unit_id <> old.unit_id then
    raise exception 'A parade cannot be moved between units' using errcode = '23514';
  end if;

  v_is_officer := private.um_has_role_in_unit(v_uid, old.unit_id, 'officer');
  v_is_admin := private.um_has_role_in_unit(v_uid, old.unit_id, 'admin');

  if new.status = old.status then
    if old.status in ('APPROVED','COMPLETED','CANCELLED') and not (v_is_officer or v_is_admin) then
      raise exception 'Only officers/admins may edit approved, completed, or cancelled parades' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.status = 'CANCELLED' then
    if nullif(btrim(new.cancel_reason), '') is null then
      raise exception 'Cancellation reason is required' using errcode = '23514';
    end if;
    if not (v_is_officer or v_is_admin) then
      raise exception 'Only officers/admins may cancel a parade' using errcode = '42501';
    end if;
    return new;
  end if;

  if old.status = 'DRAFT' and new.status = 'PROPOSED' then
    if not (
      v_is_officer or v_is_admin
      or private.um_has_role_in_unit(v_uid, old.unit_id, 'senior')
    ) then
      raise exception 'Only a senior, officer, or admin may propose a parade' using errcode = '42501';
    end if;
  elsif old.status = 'PROPOSED' and new.status = 'APPROVED' then
    if not (v_is_officer or v_is_admin) then
      raise exception 'Only an officer/admin may approve a parade' using errcode = '42501';
    end if;
    new.approved_by := v_uid;
    new.approved_at := now();
  elsif old.status = 'APPROVED' and new.status = 'COMPLETED' then
    if not (v_is_officer or v_is_admin) then
      raise exception 'Only an officer/admin may complete a parade' using errcode = '42501';
    end if;
    new.completed_at := now();
  else
    raise exception 'Invalid parade status transition: % -> %', old.status, new.status using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.has_role(uuid, public.um_role) from public, anon;
revoke all on function private.um_has_role_in_unit(uuid, uuid, public.um_role) from public, anon;
revoke all on function private.um_member_of_unit(uuid, uuid) from public, anon;
revoke all on function private.current_unit_id() from public, anon;
revoke all on function private.current_flight_id() from public, anon;
revoke all on function private.current_cadet_id() from public, anon;
revoke all on function private.um_can_read_cadet(uuid, uuid, uuid) from public, anon;
revoke all on function private.um_audit_row_change() from public, anon, authenticated;
revoke all on function private.um_set_updated_at() from public, anon, authenticated;
revoke all on function private.um_enforce_parade_transition() from public, anon, authenticated;
grant execute on function private.has_role(uuid, public.um_role) to authenticated;
grant execute on function private.um_has_role_in_unit(uuid, uuid, public.um_role) to authenticated;
grant execute on function private.um_member_of_unit(uuid, uuid) to authenticated;
grant execute on function private.current_unit_id() to authenticated;
grant execute on function private.current_flight_id() to authenticated;
grant execute on function private.current_cadet_id() to authenticated;
grant execute on function private.um_can_read_cadet(uuid, uuid, uuid) to authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'um_units','um_flights','um_profiles','um_user_roles','um_cadets','um_parade_series','um_parades',
    'um_holidays','um_leave_requests','um_attendance','um_inventory_items','um_inventory_issues',
    'um_stock_adjustments','um_fitness_metrics','um_fitness_standards','um_fitness_tests','um_fitness_results',
    'um_syllabus_items','um_cadet_syllabus_progress','um_exam_results','um_certificates','um_camps',
    'um_notifications','um_settings','um_audit_log'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- Tenant isolation: no user can see or write records for a unit where they have no role.
create policy um_units_select_member on public.um_units for select to authenticated
using (private.um_member_of_unit((select auth.uid()), id));
create policy um_units_update_admin on public.um_units for update to authenticated
using (private.um_has_role_in_unit((select auth.uid()), id, 'admin'))
with check (private.um_has_role_in_unit((select auth.uid()), id, 'admin'));

create policy um_flights_select_member on public.um_flights for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_flights_manage_command on public.um_flights for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_profiles_select_scope on public.um_profiles for select to authenticated
using (
  user_id = (select auth.uid())
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
  or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and flight_id = private.current_flight_id())
);
create policy um_profiles_update_self on public.um_profiles for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and unit_id = private.current_unit_id());
create policy um_profiles_manage_admin on public.um_profiles for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'));

create policy um_user_roles_select_self_or_admin on public.um_user_roles for select to authenticated
using (user_id = (select auth.uid()) or private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'));
create policy um_user_roles_manage_admin on public.um_user_roles for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'));

create policy um_cadets_select_scope on public.um_cadets for select to authenticated
using (
  user_id = (select auth.uid())
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
  or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and flight_id = private.current_flight_id())
);
create policy um_cadets_manage_command on public.um_cadets for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_parade_series_select_member on public.um_parade_series for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_parade_series_manage_staff on public.um_parade_series for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior'));

create policy um_parades_select_member on public.um_parades for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_parades_insert_staff on public.um_parades for insert to authenticated
with check (
  created_by = (select auth.uid()) and
  (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior'))
);
create policy um_parades_update_staff on public.um_parades for update to authenticated
using (
  private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
  or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and created_by = (select auth.uid()) and status in ('DRAFT','PROPOSED'))
)
with check (
  private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
  or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and created_by = (select auth.uid()))
);
create policy um_parades_delete_admin on public.um_parades for delete to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'));

create policy um_holidays_select_member on public.um_holidays for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_holidays_manage_command on public.um_holidays for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_leave_select_scope on public.um_leave_requests for select to authenticated
using (private.um_can_read_cadet((select auth.uid()), unit_id, cadet_id));
create policy um_leave_insert_self on public.um_leave_requests for insert to authenticated
with check (
  status = 'PENDING'
  and exists (select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_leave_requests.unit_id and c.user_id = (select auth.uid()))
);
create policy um_leave_review_staff on public.um_leave_requests for update to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_attendance_select_scope on public.um_attendance for select to authenticated
using (private.um_can_read_cadet((select auth.uid()), unit_id, cadet_id));
create policy um_attendance_insert_staff on public.um_attendance for insert to authenticated
with check (
  private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
  or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and exists (
    select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_attendance.unit_id and c.flight_id = private.current_flight_id()
  ))
);
create policy um_attendance_update_staff on public.um_attendance for update to authenticated
using (
  private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
  or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and exists (
    select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_attendance.unit_id and c.flight_id = private.current_flight_id()
  ))
)
with check (
  private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
  or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and exists (
    select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_attendance.unit_id and c.flight_id = private.current_flight_id()
  ))
);

create policy um_inventory_items_select_member on public.um_inventory_items for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_inventory_items_manage_command on public.um_inventory_items for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_inventory_issues_select_scope on public.um_inventory_issues for select to authenticated
using (private.um_can_read_cadet((select auth.uid()), unit_id, cadet_id));
create policy um_inventory_issues_request_self on public.um_inventory_issues for insert to authenticated
with check (
  status = 'REQUESTED'
  and issued_by is null
  and exists (select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_inventory_issues.unit_id and c.user_id = (select auth.uid()))
);
create policy um_inventory_issues_manage_command on public.um_inventory_issues for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_stock_adjustments_select_command on public.um_stock_adjustments for select to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));
create policy um_stock_adjustments_insert_command on public.um_stock_adjustments for insert to authenticated
with check (adjusted_by = (select auth.uid()) and (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')));

create policy um_fitness_metrics_select_member on public.um_fitness_metrics for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_fitness_metrics_manage_command on public.um_fitness_metrics for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));
create policy um_fitness_standards_select_member on public.um_fitness_standards for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_fitness_standards_manage_command on public.um_fitness_standards for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));
create policy um_fitness_tests_select_member on public.um_fitness_tests for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_fitness_tests_manage_staff on public.um_fitness_tests for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior'));
create policy um_fitness_results_select_scope on public.um_fitness_results for select to authenticated
using (private.um_can_read_cadet((select auth.uid()), unit_id, cadet_id));
create policy um_fitness_results_manage_staff on public.um_fitness_results for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and exists (select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_fitness_results.unit_id and c.flight_id = private.current_flight_id())))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and exists (select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_fitness_results.unit_id and c.flight_id = private.current_flight_id())));

create policy um_syllabus_select_member on public.um_syllabus_items for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_syllabus_manage_command on public.um_syllabus_items for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));
create policy um_syllabus_progress_select_scope on public.um_cadet_syllabus_progress for select to authenticated
using (private.um_can_read_cadet((select auth.uid()), unit_id, cadet_id));
create policy um_syllabus_progress_manage_staff on public.um_cadet_syllabus_progress for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and exists (select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_cadet_syllabus_progress.unit_id and c.flight_id = private.current_flight_id())))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer') or (private.um_has_role_in_unit((select auth.uid()), unit_id, 'senior') and exists (select 1 from public.um_cadets c where c.id = cadet_id and c.unit_id = um_cadet_syllabus_progress.unit_id and c.flight_id = private.current_flight_id())));

create policy um_exam_results_select_scope on public.um_exam_results for select to authenticated
using (private.um_can_read_cadet((select auth.uid()), unit_id, cadet_id));
create policy um_exam_results_manage_command on public.um_exam_results for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_certificates_select_scope on public.um_certificates for select to authenticated
using (private.um_can_read_cadet((select auth.uid()), unit_id, cadet_id));
create policy um_certificates_issue_command on public.um_certificates for insert to authenticated
with check (issued_by = (select auth.uid()) and (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')));
create policy um_certificates_update_command on public.um_certificates for update to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_camps_select_member on public.um_camps for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_camps_manage_command on public.um_camps for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_notifications_select_own on public.um_notifications for select to authenticated
using (recipient_id = (select auth.uid()) and private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_notifications_update_own on public.um_notifications for update to authenticated
using (recipient_id = (select auth.uid()) and private.um_member_of_unit((select auth.uid()), unit_id))
with check (recipient_id = (select auth.uid()) and private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_notifications_insert_command on public.um_notifications for insert to authenticated
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

create policy um_settings_select_member on public.um_settings for select to authenticated
using (private.um_member_of_unit((select auth.uid()), unit_id));
create policy um_settings_manage_admin on public.um_settings for all to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'))
with check (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin'));

create policy um_audit_select_command on public.um_audit_log for select to authenticated
using (private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin') or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer'));

-- Audit all core operational changes; the audit table itself is append-only to app users.
do $$
declare t text;
begin
  foreach t in array array[
    'um_units','um_flights','um_profiles','um_user_roles','um_cadets','um_parade_series','um_parades',
    'um_holidays','um_leave_requests','um_attendance','um_inventory_items','um_inventory_issues',
    'um_stock_adjustments','um_fitness_metrics','um_fitness_standards','um_fitness_tests','um_fitness_results',
    'um_syllabus_items','um_cadet_syllabus_progress','um_exam_results','um_certificates','um_camps',
    'um_notifications','um_settings'
  ] loop
    execute format('drop trigger if exists um_audit_change on public.%I', t);
    execute format('create trigger um_audit_change after insert or update or delete on public.%I for each row execute function private.um_audit_row_change()', t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'um_units','um_flights','um_profiles','um_cadets','um_parades','um_leave_requests','um_attendance',
    'um_inventory_items','um_inventory_issues','um_fitness_metrics','um_fitness_standards','um_fitness_results',
    'um_cadet_syllabus_progress','um_notifications','um_settings'
  ] loop
    execute format('drop trigger if exists um_touch_updated_at on public.%I', t);
    execute format('create trigger um_touch_updated_at before update on public.%I for each row execute function private.um_set_updated_at()', t);
  end loop;
end $$;

drop trigger if exists um_parade_status_guard on public.um_parades;
create trigger um_parade_status_guard before insert or update of status, unit_id on public.um_parades
for each row execute function private.um_enforce_parade_transition();

-- Anonymous clients receive no privileges on the new Unit Manager tables.
grant usage, select on sequence public.um_audit_log_id_seq to authenticated;


-- Composite foreign keys prevent valid unit memberships from being combined
-- with records owned by another unit. These are essential to tenant isolation.
alter table public.um_parades add constraint um_parades_unit_id_unique unique (unit_id, id);
alter table public.um_attendance add constraint um_attendance_parade_same_unit_fk
  foreign key (unit_id, parade_id) references public.um_parades(unit_id, id) on delete cascade;
alter table public.um_attendance add constraint um_attendance_cadet_same_unit_fk
  foreign key (unit_id, cadet_id) references public.um_cadets(unit_id, id) on delete cascade;
alter table public.um_leave_requests add constraint um_leave_cadet_same_unit_fk
  foreign key (unit_id, cadet_id) references public.um_cadets(unit_id, id) on delete cascade;
alter table public.um_inventory_issues add constraint um_issue_item_same_unit_fk
  foreign key (unit_id, item_id) references public.um_inventory_items(unit_id, id) on delete restrict;
alter table public.um_inventory_issues add constraint um_issue_cadet_same_unit_fk
  foreign key (unit_id, cadet_id) references public.um_cadets(unit_id, id) on delete restrict;
alter table public.um_stock_adjustments add constraint um_stock_item_same_unit_fk
  foreign key (unit_id, item_id) references public.um_inventory_items(unit_id, id) on delete restrict;
alter table public.um_fitness_standards add constraint um_standards_metric_same_unit_fk
  foreign key (unit_id, metric_id) references public.um_fitness_metrics(unit_id, id) on delete cascade;
alter table public.um_fitness_tests add constraint um_fitness_test_metric_same_unit_fk
  foreign key (unit_id, metric_id) references public.um_fitness_metrics(unit_id, id) on delete restrict;
alter table public.um_fitness_results add constraint um_fitness_result_test_same_unit_fk
  foreign key (unit_id, test_id) references public.um_fitness_tests(unit_id, id) on delete cascade;
alter table public.um_fitness_results add constraint um_fitness_result_cadet_same_unit_fk
  foreign key (unit_id, cadet_id) references public.um_cadets(unit_id, id) on delete cascade;
alter table public.um_cadet_syllabus_progress add constraint um_progress_cadet_same_unit_fk
  foreign key (unit_id, cadet_id) references public.um_cadets(unit_id, id) on delete cascade;
alter table public.um_cadet_syllabus_progress add constraint um_progress_topic_same_unit_fk
  foreign key (unit_id, syllabus_item_id) references public.um_syllabus_items(unit_id, id) on delete cascade;
alter table public.um_exam_results add constraint um_exam_cadet_same_unit_fk
  foreign key (unit_id, cadet_id) references public.um_cadets(unit_id, id) on delete cascade;
alter table public.um_certificates add constraint um_certificate_cadet_same_unit_fk
  foreign key (unit_id, cadet_id) references public.um_cadets(unit_id, id) on delete restrict;
