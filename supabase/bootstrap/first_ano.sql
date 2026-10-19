-- One-time NTS ANO bootstrap.
-- Run only in Supabase SQL Editor as a trusted project/database owner,
-- after inviting panbalanpi@gmail.com through Authentication -> Users.
-- This script never creates an Auth user or sets a password.
do $$
declare
  target_id uuid;
  auth_count integer;
  profile_count integer;
  updated_count integer;
begin
  select count(*), min(id)
    into auth_count, target_id
    from auth.users
   where lower(email) = lower('panbalanpi@gmail.com');

  if auth_count <> 1 then
    raise exception 'Expected exactly one Auth user for panbalanpi@gmail.com; found %.', auth_count;
  end if;

  select count(*) into profile_count
    from public.profiles where id = target_id;

  if profile_count <> 1 then
    raise exception 'Expected exactly one profile linked to the invited Auth user; found %.', profile_count;
  end if;

  update public.profiles
     set role = 'ANO'::public.command_role,
         rank_title = 'ANO',
         is_active = true
   where id = target_id;

  get diagnostics updated_count = row_count;
  if updated_count <> 1 then
    raise exception 'ANO bootstrap updated % profiles; expected exactly one.', updated_count;
  end if;
end $$;

-- Verify the exact result before leaving SQL Editor.
select u.email, p.id, p.full_name, p.role::text as role, p.is_active
  from auth.users u
  join public.profiles p on p.id = u.id
 where lower(u.email) = lower('panbalanpi@gmail.com');
