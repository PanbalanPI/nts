create or replace function public.um_adjust_stock(p_item_id uuid,p_quantity_delta integer,p_reason text)
returns integer language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_item public.um_inventory_items%rowtype; v_issued integer; v_new_qty integer;
begin
  v_unit:=private.current_unit_id();
  if v_unit is null or not (private.um_has_role_in_unit(auth.uid(),v_unit,'admin') or private.um_has_role_in_unit(auth.uid(),v_unit,'officer')) then
    raise exception 'Only officers/admins may adjust stock' using errcode='42501';
  end if;
  if p_quantity_delta is null or p_quantity_delta=0 or length(trim(coalesce(p_reason,'')))<4 then
    raise exception 'Provide a non-zero quantity change and a reason of at least four characters' using errcode='22023';
  end if;
  select * into v_item from public.um_inventory_items where id=p_item_id and unit_id=v_unit for update;
  if not found then raise exception 'Inventory item not found' using errcode='P0002'; end if;
  if lower(v_item.item_code || ' ' || v_item.name || ' ' || v_item.description) ~ '(weapon|rifle|firearm|gun|ammunition|ammo)' then
    raise exception 'Weapon-related inventory changes are not supported by this application.' using errcode='42501';
  end if;
  select coalesce(sum(qty),0)::integer into v_issued from public.um_inventory_issues where unit_id=v_unit and item_id=p_item_id and status='ISSUED';
  v_new_qty:=v_item.total_qty+p_quantity_delta;
  if v_new_qty < v_issued or v_new_qty < 0 then raise exception 'Stock cannot be reduced below the quantity currently issued (%)',v_issued using errcode='23514'; end if;
  update public.um_inventory_items set total_qty=v_new_qty,updated_at=now() where id=p_item_id and unit_id=v_unit;
  insert into public.um_stock_adjustments(unit_id,item_id,quantity_delta,reason,adjusted_by)
  values(v_unit,p_item_id,p_quantity_delta,trim(p_reason),auth.uid());
  return v_new_qty;
end;
$$;
grant execute on function public.um_adjust_stock(uuid,integer,text) to authenticated;
revoke all on function public.um_adjust_stock(uuid,integer,text) from public,anon;
