-- Hardening follow-up for NCC Unit Manager foundation.
-- Keep the live schema and migration history aligned with the security model.

-- Remove duplicate composite uniqueness on parades; the original table already
-- owns an equivalent (unit_id,id) key used by same-unit foreign keys.
alter table public.um_parades drop constraint if exists um_parades_unit_id_unique;

-- A profile owner may update contact details, but not unit, flight, identity,
-- active status, or password-change enforcement. Role changes stay in um_user_roles.
create or replace function private.um_guard_profile_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.user_id = auth.uid()
     and not (
       private.um_has_role_in_unit(auth.uid(), old.unit_id, 'admin')
       or private.um_has_role_in_unit(auth.uid(), old.unit_id, 'officer')
     ) then
    if new.user_id is distinct from old.user_id
      or new.unit_id is distinct from old.unit_id
      or new.flight_id is distinct from old.flight_id
      or new.full_name is distinct from old.full_name
      or new.is_active is distinct from old.is_active
      or new.force_password_change is distinct from old.force_password_change then
      raise exception 'Profile owners may only update contact details' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.um_guard_profile_update() from public, anon, authenticated;
drop trigger if exists um_profile_update_guard on public.um_profiles;
create trigger um_profile_update_guard before update on public.um_profiles
for each row execute function private.um_guard_profile_update();

-- Syllabus completion and sign-off are officer/admin controlled, not senior-controlled.
drop policy if exists um_syllabus_progress_manage_staff on public.um_cadet_syllabus_progress;
create policy um_syllabus_progress_manage_command on public.um_cadet_syllabus_progress
for all to authenticated
using (
  private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
)
with check (
  private.um_has_role_in_unit((select auth.uid()), unit_id, 'admin')
  or private.um_has_role_in_unit((select auth.uid()), unit_id, 'officer')
);

-- Direct table writes cannot grant a kit issue or mark a kit returned. These
-- state changes will be performed by validated transactional RPCs in a later step.
create or replace function private.um_guard_inventory_issue_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_admin boolean;
  v_officer boolean;
begin
  v_admin := private.um_has_role_in_unit(auth.uid(), old.unit_id, 'admin');
  v_officer := private.um_has_role_in_unit(auth.uid(), old.unit_id, 'officer');

  if tg_op = 'INSERT' then
    if new.status <> 'REQUESTED' or new.issued_by is not null or new.issued_at is not null or new.returned_at is not null then
      raise exception 'Inventory issues must be created as requests; use the issue workflow' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.unit_id <> old.unit_id or new.item_id <> old.item_id or new.cadet_id <> old.cadet_id or new.qty <> old.qty then
    if not (v_admin or v_officer) then
      raise exception 'Only officers/admins may modify inventory issue identity or quantity' using errcode = '42501';
    end if;
  end if;

  if new.status is distinct from old.status
     or new.issued_by is distinct from old.issued_by
     or new.issued_at is distinct from old.issued_at
     or new.returned_at is distinct from old.returned_at
     or new.condition_on_return is distinct from old.condition_on_return then
    raise exception 'Inventory issue/return state must be changed through the validated inventory RPC' using errcode = '42501';
  end if;

  return new;
end;
$$;
revoke all on function private.um_guard_inventory_issue_state() from public, anon, authenticated;
drop trigger if exists um_inventory_issue_state_guard on public.um_inventory_issues;
create trigger um_inventory_issue_state_guard before insert or update on public.um_inventory_issues
for each row execute function private.um_guard_inventory_issue_state();
