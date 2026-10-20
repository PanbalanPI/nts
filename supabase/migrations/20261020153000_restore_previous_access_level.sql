-- Preserve the previous application access level when ANO temporarily
-- promotes a Senior to delegated top administrator.
create or replace function public.um_set_unit_admin_access(
  p_actor uuid, p_target uuid, p_grant boolean, p_reason text default null
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_unit uuid;
  v_target_level text;
  v_previous_role text;
  v_previous_level text;
  v_count integer;
begin
  select unit_id into v_unit from public.um_profiles
  where user_id=p_actor and access_level='ano' and is_active=true for update;
  if v_unit is null then raise exception 'Only the active ANO can manage delegated administrators.'; end if;
  if p_target=p_actor then raise exception 'The ANO cannot change their own administrator access.'; end if;
  perform 1 from public.um_units where id=v_unit for update;

  select access_level into v_target_level from public.um_profiles
  where user_id=p_target and unit_id=v_unit and is_active=true for update;
  if not found then raise exception 'Target member is not active in this unit.'; end if;
  select role::text into v_previous_role from public.um_user_roles
  where user_id=p_target and unit_id=v_unit;

  if p_grant then
    if v_target_level='ano' then raise exception 'The ANO cannot be delegated as a unit administrator.'; end if;
    select count(*) into v_count from public.um_profiles
    where unit_id=v_unit and access_level='unit_admin' and is_active=true and user_id<>p_target;
    if v_count>=4 then raise exception 'All four delegated administrator slots are in use.'; end if;
    update public.um_profiles set access_level='unit_admin',updated_at=now()
    where user_id=p_target and unit_id=v_unit;
    update public.um_user_roles set role='admin'::public.um_role,granted_by=p_actor
    where user_id=p_target and unit_id=v_unit;
    insert into public.um_unit_admin_audit(unit_id,target_user_id,changed_by,action,reason,metadata)
    values(v_unit,p_target,p_actor,'granted',nullif(trim(coalesce(p_reason,'')),''),
      jsonb_build_object('access_level','unit_admin','previous_role',coalesce(v_previous_role,'cadet'),
        'previous_access_level',v_target_level));
    return jsonb_build_object('ok',true,'access_level','unit_admin');
  else
    if v_target_level<>'unit_admin' then raise exception 'This member is not a delegated administrator.'; end if;
    select coalesce(nullif(a.metadata->>'previous_access_level',''),'user')
      into v_previous_level
    from public.um_unit_admin_audit a
    where a.unit_id=v_unit and a.target_user_id=p_target and a.action='granted'
      and coalesce(a.metadata->>'access_level','unit_admin')='unit_admin'
    order by a.created_at desc limit 1;
    update public.um_profiles set access_level=coalesce(v_previous_level,'user'),updated_at=now()
    where user_id=p_target and unit_id=v_unit;
    update public.um_user_roles set role=coalesce(nullif((
      select a.metadata->>'previous_role' from public.um_unit_admin_audit a
      where a.unit_id=v_unit and a.target_user_id=p_target and a.action='granted'
        and coalesce(a.metadata->>'access_level','unit_admin')='unit_admin'
      order by a.created_at desc limit 1
    ),''),'cadet')::public.um_role,granted_by=p_actor
    where user_id=p_target and unit_id=v_unit;
    insert into public.um_unit_admin_audit(unit_id,target_user_id,changed_by,action,reason,metadata)
    values(v_unit,p_target,p_actor,'revoked',nullif(trim(coalesce(p_reason,'')),''),
      jsonb_build_object('access_level','unit_admin','restored_access_level',coalesce(v_previous_level,'user')));
    return jsonb_build_object('ok',true,'access_level',coalesce(v_previous_level,'user'));
  end if;
end;
$$;
revoke all on function public.um_set_unit_admin_access(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.um_set_unit_admin_access(uuid,uuid,boolean,text) to service_role;
