-- Keep inventory workflows limited to ordinary unit kit; no weapon issuance is supported.
update public.um_inventory_items set item_code='DEMO-CONE-SET',name='Drill cone set',description='Parade training equipment'
where item_code='DEMO-DRILL-RIFLE' and unit_id in (select id from public.um_units);
create or replace function public.um_issue_item(p_item_id uuid,p_cadet_id uuid,p_qty integer,p_due_date date default null)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_item public.um_inventory_items%rowtype; v_available integer; v_issue uuid;
begin
  v_unit := private.current_unit_id();
  if v_unit is null or not (private.um_has_role_in_unit(auth.uid(),v_unit,'admin') or private.um_has_role_in_unit(auth.uid(),v_unit,'officer')) then
    raise exception 'Only officers/admins may issue inventory' using errcode='42501';
  end if;
  if p_qty is null or p_qty < 1 then raise exception 'Quantity must be positive' using errcode='22023'; end if;
  select * into v_item from public.um_inventory_items where id=p_item_id and unit_id=v_unit and is_active for update;
  if not found then raise exception 'Inventory item not found or inactive' using errcode='P0002'; end if;
  if lower(v_item.item_code || ' ' || v_item.name || ' ' || v_item.description) ~ '(weapon|rifle|firearm|gun|ammunition|ammo)' then
    raise exception 'Weapon-related items cannot be issued through this application. Use the unit’s approved supervised process.' using errcode='42501';
  end if;
  if not exists(select 1 from public.um_cadets where id=p_cadet_id and unit_id=v_unit and status='ACTIVE') then raise exception 'Cadet not found or inactive' using errcode='P0002'; end if;
  select v_item.total_qty - coalesce(sum(i.qty) filter(where i.status='ISSUED'),0)::integer into v_available
  from public.um_inventory_issues i where i.unit_id=v_unit and i.item_id=p_item_id;
  if p_qty > v_available then raise exception 'Insufficient stock. Available quantity: %',v_available using errcode='23514'; end if;
  insert into private.um_inventory_rpc_context values(txid_current(),auth.uid(),'issue') on conflict do nothing;
  insert into public.um_inventory_issues(unit_id,item_id,cadet_id,qty,due_date,status,issued_by,issued_at)
  values(v_unit,p_item_id,p_cadet_id,p_qty,p_due_date,'ISSUED',auth.uid(),now()) returning id into v_issue;
  delete from private.um_inventory_rpc_context where txid=txid_current() and user_id=auth.uid() and action='issue';
  return v_issue;
end;
$$;
grant execute on function public.um_issue_item(uuid,uuid,integer,date) to authenticated;
revoke all on function public.um_issue_item(uuid,uuid,integer,date) from public,anon;
