-- NTS unit registration approval and ANO/delegated administrator access.
-- Additive migration over the existing um_* schema.

begin;

alter table public.um_profiles
  add column if not exists appointment text,
  add column if not exists access_level text not null default 'user';

alter table public.um_profiles
  drop constraint if exists um_profiles_access_level_check;
alter table public.um_profiles
  add constraint um_profiles_access_level_check
  check (access_level in ('user', 'ano', 'unit_admin'));

-- Preserve the existing first unit administrator as the ANO; all other
-- existing members default to ordinary User access unless explicitly assigned.
update public.um_profiles p
set access_level = 'ano'
from public.um_user_roles r
where r.user_id = p.user_id
  and r.unit_id = p.unit_id
  and r.role = 'admin'
  and p.access_level = 'user';

create unique index if not exists um_one_active_ano_per_unit
  on public.um_profiles (unit_id)
  where access_level = 'ano' and is_active = true;

create table if not exists public.um_platform_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role = 'super_admin'),
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.um_platform_roles enable row level security;
revoke insert, update, delete, truncate, references, trigger on public.um_platform_roles from anon, authenticated;
grant select on public.um_platform_roles to authenticated, service_role;

create or replace function public.um_is_platform_super_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.um_platform_roles r
    where r.user_id = p_user_id and r.role = 'super_admin'
  );
$$;
revoke all on function public.um_is_platform_super_admin(uuid) from public, anon;
grant execute on function public.um_is_platform_super_admin(uuid) to authenticated, service_role;

drop policy if exists um_platform_roles_select_self_or_super_admin on public.um_platform_roles;
create policy um_platform_roles_select_self_or_super_admin
on public.um_platform_roles for select to authenticated
using (user_id = auth.uid() or public.um_is_platform_super_admin());

drop policy if exists um_units_select_super_admin on public.um_units;
create policy um_units_select_super_admin
on public.um_units for select to authenticated
using (public.um_is_platform_super_admin());

create table if not exists public.um_unit_registration_requests (
  id uuid primary key default gen_random_uuid(),
  applicant_user_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  regimental_no text not null,
  rank_title text not null,
  appointment text,
  unit_name text not null,
  unit_code text not null,
  timezone text not null default 'Asia/Kolkata',
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  created_unit_id uuid references public.um_units(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or (status <> 'pending' and reviewed_by is not null and reviewed_at is not null)
  )
);
create unique index if not exists um_one_pending_registration_code
  on public.um_unit_registration_requests (lower(unit_code))
  where status = 'pending';
create unique index if not exists um_one_pending_registration_regimental
  on public.um_unit_registration_requests (lower(regimental_no))
  where status = 'pending';
create index if not exists um_registration_queue_idx
  on public.um_unit_registration_requests (status, created_at desc);

alter table public.um_unit_registration_requests enable row level security;
revoke insert, update, delete, truncate, references, trigger on public.um_unit_registration_requests from anon, authenticated;
grant select on public.um_unit_registration_requests to authenticated, service_role;

drop policy if exists um_registration_read_own_or_super_admin on public.um_unit_registration_requests;
create policy um_registration_read_own_or_super_admin
on public.um_unit_registration_requests for select to authenticated
using (
  applicant_user_id = auth.uid()
  or public.um_is_platform_super_admin()
);

create table if not exists public.um_unit_admin_audit (
  id bigint generated always as identity primary key,
  unit_id uuid references public.um_units(id) on delete cascade,
  target_user_id uuid references auth.users(id) on delete set null,
  changed_by uuid references auth.users(id) on delete set null,
  action text not null check (action in ('granted', 'revoked', 'registration_approved', 'registration_rejected')),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.um_unit_admin_audit enable row level security;
revoke insert, update, delete, truncate, references, trigger on public.um_unit_admin_audit from anon, authenticated;
grant select on public.um_unit_admin_audit to authenticated, service_role;
drop policy if exists um_unit_admin_audit_select_ano_or_super_admin on public.um_unit_admin_audit;
create policy um_unit_admin_audit_select_ano_or_super_admin
on public.um_unit_admin_audit for select to authenticated
using (
  public.um_is_platform_super_admin()
  or exists (
    select 1 from public.um_profiles p
    where p.user_id = auth.uid()
      and p.unit_id = um_unit_admin_audit.unit_id
      and p.access_level = 'ano'
      and p.is_active = true
  )
);

-- Prevent direct client-side privilege escalation and enforce the four delegated
-- administrator slots under a per-unit row lock.
create or replace function public.um_guard_access_level()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if auth.role() is distinct from 'service_role' then
    if tg_op = 'INSERT' and new.access_level <> 'user' then
      raise exception 'Elevated access must be granted by a trusted server workflow.';
    elsif tg_op = 'UPDATE' and new.access_level is distinct from old.access_level then
      raise exception 'Elevated access must be changed by a trusted server workflow.';
    end if;
  end if;

  if new.access_level = 'ano' and new.is_active then
    if tg_op = 'UPDATE' and old.unit_id = new.unit_id and old.access_level = 'ano' then
      return new;
    end if;
    if exists (
      select 1 from public.um_profiles p
      where p.unit_id = new.unit_id and p.access_level = 'ano'
        and p.is_active = true and p.user_id <> new.user_id
    ) then
      raise exception 'Each unit can have only one active ANO.';
    end if;
  end if;

  if new.access_level = 'unit_admin' and new.is_active then
    perform 1 from public.um_units where id = new.unit_id for update;
    select count(*) into v_count
    from public.um_profiles p
    where p.unit_id = new.unit_id
      and p.access_level = 'unit_admin'
      and p.is_active = true
      and p.user_id <> new.user_id;
    if v_count >= 4 then
      raise exception 'A unit may have at most four additional administrators.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_um_guard_access_level on public.um_profiles;
create trigger trg_um_guard_access_level
before insert or update of access_level, unit_id, is_active
on public.um_profiles
for each row execute function public.um_guard_access_level();

-- Atomic approval/rejection: unit, ANO profile, role assignment, request status,
-- and audit record commit together.
create or replace function public.um_review_unit_registration(
  p_request_id uuid,
  p_decision text,
  p_reason text,
  p_reviewer uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.um_unit_registration_requests%rowtype;
  v_unit public.um_units%rowtype;
  v_email text;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'Decision must be approve or reject.';
  end if;
  if not public.um_is_platform_super_admin(p_reviewer) then
    raise exception 'Only the Platform Super Admin can review unit registrations.';
  end if;
  if p_decision = 'reject' and length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'A rejection reason of at least five characters is required.';
  end if;

  select * into r from public.um_unit_registration_requests
  where id = p_request_id for update;
  if not found then raise exception 'Registration request not found.'; end if;
  if r.status <> 'pending' then raise exception 'This request has already been reviewed.'; end if;

  if p_decision = 'reject' then
    update public.um_unit_registration_requests
    set status = 'rejected', reviewed_by = p_reviewer, reviewed_at = now(),
        review_reason = trim(p_reason), updated_at = now()
    where id = r.id;
    insert into public.um_unit_admin_audit(unit_id, target_user_id, changed_by, action, reason, metadata)
    values (null, r.applicant_user_id, p_reviewer, 'registration_rejected', trim(p_reason),
      jsonb_build_object('request_id', r.id, 'unit_code', r.unit_code));
    return jsonb_build_object('ok', true, 'status', 'rejected');
  end if;

  if exists (select 1 from public.um_units u where lower(u.code) = lower(r.unit_code)) then
    raise exception 'A unit with this code already exists.';
  end if;

  insert into public.um_units(name, code, timezone, is_active)
  values (trim(r.unit_name), upper(trim(r.unit_code)), coalesce(nullif(r.timezone, ''), 'Asia/Kolkata'), true)
  returning * into v_unit;

  select lower(coalesce(u.email, r.regimental_no || '@unit.local'))
    into v_email from auth.users u where u.id = r.applicant_user_id;

  insert into public.um_profiles(
    user_id, unit_id, full_name, email, regimental_no, rank_title, appointment,
    access_level, force_password_change, is_active
  )
  values (
    r.applicant_user_id, v_unit.id, r.full_name, coalesce(v_email, lower(r.regimental_no) || '@unit.local'),
    r.regimental_no, r.rank_title, r.appointment, 'ano', false, true
  );

  insert into public.um_user_roles(user_id, unit_id, role, granted_by)
  values (r.applicant_user_id, v_unit.id, 'admin'::public.um_role, p_reviewer);

  update public.um_unit_registration_requests
  set status = 'approved', created_unit_id = v_unit.id, reviewed_by = p_reviewer,
      reviewed_at = now(), review_reason = null, updated_at = now()
  where id = r.id;

  insert into public.um_unit_admin_audit(unit_id, target_user_id, changed_by, action, reason, metadata)
  values (v_unit.id, r.applicant_user_id, p_reviewer, 'registration_approved', null,
    jsonb_build_object('request_id', r.id, 'unit_code', v_unit.code));

  insert into public.um_audit_log(unit_id, actor_id, action, table_name, record_id, after_data)
  values (v_unit.id, p_reviewer, 'unit_registration_approved', 'um_units', v_unit.id::text,
    jsonb_build_object('unit_name', v_unit.name, 'unit_code', v_unit.code, 'ano_user_id', r.applicant_user_id));

  return jsonb_build_object('ok', true, 'status', 'approved', 'unit_id', v_unit.id);
end;
$$;

revoke all on function public.um_review_unit_registration(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.um_review_unit_registration(uuid, text, text, uuid) to service_role;


-- Atomically grant/revoke one of the ANO's four delegated administrator slots.
create or replace function public.um_set_unit_admin_access(
  p_actor uuid,
  p_target uuid,
  p_grant boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit uuid;
  v_target_level text;
  v_previous_role text;
  v_count integer;
begin
  select unit_id into v_unit
  from public.um_profiles
  where user_id = p_actor and access_level = 'ano' and is_active = true
  for update;
  if v_unit is null then
    raise exception 'Only the active ANO can manage delegated administrators.';
  end if;
  if p_target = p_actor then
    raise exception 'The ANO cannot change their own administrator access.';
  end if;

  perform 1 from public.um_units where id = v_unit for update;
  select access_level into v_target_level
  from public.um_profiles
  where user_id = p_target and unit_id = v_unit and is_active = true
  for update;
  if not found then raise exception 'Target member is not active in this unit.'; end if;

  select role::text into v_previous_role
  from public.um_user_roles
  where user_id = p_target and unit_id = v_unit;

  if p_grant then
    if v_target_level = 'ano' then raise exception 'The ANO cannot be delegated as a unit administrator.'; end if;
    select count(*) into v_count from public.um_profiles
    where unit_id = v_unit and access_level = 'unit_admin' and is_active = true and user_id <> p_target;
    if v_count >= 4 then raise exception 'All four delegated administrator slots are in use.'; end if;

    update public.um_profiles set access_level = 'unit_admin', updated_at = now()
    where user_id = p_target and unit_id = v_unit;
    update public.um_user_roles set role = 'admin'::public.um_role, granted_by = p_actor
    where user_id = p_target and unit_id = v_unit;
    insert into public.um_unit_admin_audit(unit_id,target_user_id,changed_by,action,reason,metadata)
    values(v_unit,p_target,p_actor,'granted',nullif(trim(coalesce(p_reason,'')), ''),
      jsonb_build_object('previous_role',coalesce(v_previous_role,'cadet')));
    return jsonb_build_object('ok',true,'access_level','unit_admin');
  else
    if v_target_level <> 'unit_admin' then raise exception 'This member is not a delegated administrator.'; end if;
    update public.um_profiles set access_level = 'user', updated_at = now()
    where user_id = p_target and unit_id = v_unit;
    update public.um_user_roles
    set role = coalesce(nullif((select a.metadata->>'previous_role'
      from public.um_unit_admin_audit a
      where a.unit_id = v_unit and a.target_user_id = p_target and a.action = 'granted'
      order by a.created_at desc limit 1), ''), 'cadet')::public.um_role,
      granted_by = p_actor
    where user_id = p_target and unit_id = v_unit;
    insert into public.um_unit_admin_audit(unit_id,target_user_id,changed_by,action,reason,metadata)
    values(v_unit,p_target,p_actor,'revoked',nullif(trim(coalesce(p_reason,'')), ''),'{}'::jsonb);
    return jsonb_build_object('ok',true,'access_level','user');
  end if;
end;
$$;
revoke all on function public.um_set_unit_admin_access(uuid, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.um_set_unit_admin_access(uuid, uuid, boolean, text) to service_role;

commit;
