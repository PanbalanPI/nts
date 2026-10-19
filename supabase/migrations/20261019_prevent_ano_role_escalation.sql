create or replace function private.prevent_ano_role_escalation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.role = 'ANO'::public.command_role
     and old.role is distinct from new.role
     and coalesce(auth.role(), '') <> 'service_role'
     and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'ANO role assignment is restricted to controlled database administration.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_ano_role_escalation on public.profiles;
create trigger prevent_ano_role_escalation
before update of role on public.profiles
for each row execute function private.prevent_ano_role_escalation();

comment on function private.prevent_ano_role_escalation() is
  'Prevents normal authenticated sessions from granting ANO authority; initial ANO bootstrap must be performed by a trusted database administrator.';
