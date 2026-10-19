-- NCC Unit Manager business operations and transactional RPCs.
create table if not exists private.um_inventory_rpc_context (
  txid bigint not null,
  user_id uuid not null,
  action text not null check (action in ('issue','return')),
  primary key (txid,user_id,action)
);
revoke all on private.um_inventory_rpc_context from public, anon, authenticated;

create or replace function private.um_guard_inventory_issue_state()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_action text;
begin
  select c.action into v_action
  from private.um_inventory_rpc_context c
  where c.txid = txid_current() and c.user_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    if v_action = 'issue' and new.status = 'ISSUED' and new.issued_by = auth.uid() then
      return new;
    end if;
    if new.status <> 'REQUESTED' or new.issued_by is not null or new.issued_at is not null or new.returned_at is not null then
      raise exception 'Inventory issues must be created as requests or through the issue RPC' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.unit_id <> old.unit_id or new.item_id <> old.item_id or new.cadet_id <> old.cadet_id or new.qty <> old.qty then
    if not (private.um_has_role_in_unit(auth.uid(), old.unit_id, 'admin') or private.um_has_role_in_unit(auth.uid(), old.unit_id, 'officer')) then
      raise exception 'Only officers/admins may modify inventory issue identity or quantity' using errcode = '42501';
    end if;
  end if;

  if v_action = 'return' and old.status = 'ISSUED' and new.status = 'RETURNED'
     and new.returned_at is not null then
    return new;
  end if;
  if v_action = 'issue' and old.status = 'REQUESTED' and new.status = 'ISSUED'
     and new.issued_by = auth.uid() and new.issued_at is not null then
    return new;
  end if;
  if new.status is distinct from old.status
     or new.issued_by is distinct from old.issued_by
     or new.issued_at is distinct from old.issued_at
     or new.returned_at is distinct from old.returned_at
     or new.condition_on_return is distinct from old.condition_on_return then
    raise exception 'Inventory issue/return state must use the validated RPC' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.um_generate_parade_series(
  p_title text, p_parade_type public.um_parade_type, p_venue text,
  p_description text, p_weekday smallint, p_start_date date, p_end_date date,
  p_start_time time, p_end_time time, p_target_flights uuid[] default '{}',
  p_target_years smallint[] default '{}'
) returns table(series_id uuid, generated_count integer)
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_series uuid; v_date date; v_count integer := 0;
begin
  v_unit := private.current_unit_id();
  if v_unit is null or not (
    private.um_has_role_in_unit(auth.uid(),v_unit,'admin') or
    private.um_has_role_in_unit(auth.uid(),v_unit,'officer') or
    private.um_has_role_in_unit(auth.uid(),v_unit,'senior')
  ) then raise exception 'Not authorized to schedule parades' using errcode='42501'; end if;
  if p_end_date < p_start_date or p_end_time <= p_start_time or p_weekday not between 0 and 6 then
    raise exception 'Invalid parade series dates or times' using errcode='22023';
  end if;
  if exists(select 1 from unnest(coalesce(p_target_flights,'{}'::uuid[])) f where not exists(select 1 from public.um_flights x where x.id=f and x.unit_id=v_unit and x.is_active)) then
    raise exception 'A target flight is not part of this unit' using errcode='22023';
  end if;
  insert into public.um_parade_series(unit_id,created_by,title,parade_type,venue,description,weekday,start_date,end_date,start_time,end_time,target_flights,target_years)
  values(v_unit,auth.uid(),trim(p_title),p_parade_type,trim(p_venue),coalesce(p_description,''),p_weekday,p_start_date,p_end_date,p_start_time,p_end_time,coalesce(p_target_flights,'{}'),coalesce(p_target_years,'{}'))
  returning id into v_series;
  v_date := p_start_date + ((p_weekday - extract(dow from p_start_date)::integer + 7) % 7);
  while v_date <= p_end_date loop
    if not exists(select 1 from public.um_holidays h where h.unit_id=v_unit and h.holiday_date=v_date) then
      insert into public.um_parades(unit_id,series_id,created_by,title,parade_date,starts_at,ends_at,venue,parade_type,description,target_flights,target_years,status)
      values(v_unit,v_series,auth.uid(),trim(p_title),v_date,p_start_time,p_end_time,trim(p_venue),p_parade_type,coalesce(p_description,''),coalesce(p_target_flights,'{}'),coalesce(p_target_years,'{}'),'DRAFT');
      v_count := v_count + 1;
    end if;
    v_date := v_date + 7;
  end loop;
  return query select v_series,v_count;
end;
$$;

create or replace function public.um_save_attendance(p_parade_id uuid, p_rows jsonb)
returns integer language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_flight uuid; v_status public.um_parade_status; v_date date; v_role public.um_role; v_count integer := 0; v_row jsonb; v_cadet uuid; v_att public.um_attendance_status; v_notes text;
begin
  v_unit := private.current_unit_id();
  select r.role into v_role from public.um_user_roles r where r.user_id=auth.uid() and r.unit_id=v_unit;
  if v_unit is null or not (v_role in ('admin','officer','senior')) then raise exception 'Not authorized to mark attendance' using errcode='42501'; end if;
  select p.status,p.parade_date into v_status,v_date from public.um_parades p where p.id=p_parade_id and p.unit_id=v_unit for update;
  if not found then raise exception 'Parade not found' using errcode='P0002'; end if;
  if v_status <> 'APPROVED' then raise exception 'Attendance can only be saved for approved parades' using errcode='55000'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 1000 then raise exception 'Rows must be a JSON array of at most 1000 records' using errcode='22023'; end if;
  v_flight := private.current_flight_id();
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_cadet := (v_row->>'cadet_id')::uuid;
    v_att := (v_row->>'status')::public.um_attendance_status;
    v_notes := left(coalesce(v_row->>'notes',''),1000);
    if not exists(select 1 from public.um_cadets c where c.id=v_cadet and c.unit_id=v_unit and c.status='ACTIVE' and (v_role <> 'senior' or c.flight_id=v_flight)) then
      raise exception 'Cadet is outside the authorized unit or flight' using errcode='42501';
    end if;
    if exists(select 1 from public.um_leave_requests l join public.um_cadets c on c.id=l.cadet_id and c.unit_id=l.unit_id where c.id=v_cadet and l.unit_id=v_unit and l.status='APPROVED' and v_date between l.starts_on and l.ends_on) then
      v_att := 'LEAVE';
    end if;
    insert into public.um_attendance(unit_id,parade_id,cadet_id,status,notes,marked_by)
    values(v_unit,p_parade_id,v_cadet,v_att,v_notes,auth.uid())
    on conflict(parade_id,cadet_id) do update set status=excluded.status,notes=excluded.notes,marked_by=excluded.marked_by,updated_at=now();
    v_count := v_count+1;
  end loop;
  return v_count;
end;
$$;

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

create or replace function public.um_return_item(p_issue_id uuid,p_condition public.um_inventory_condition,p_notes text default '')
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid;
begin
  v_unit := private.current_unit_id();
  if v_unit is null or not (private.um_has_role_in_unit(auth.uid(),v_unit,'admin') or private.um_has_role_in_unit(auth.uid(),v_unit,'officer')) then
    raise exception 'Only officers/admins may return inventory' using errcode='42501';
  end if;
  insert into private.um_inventory_rpc_context values(txid_current(),auth.uid(),'return') on conflict do nothing;
  update public.um_inventory_issues set status='RETURNED',returned_at=now(),condition_on_return=p_condition,return_notes=left(coalesce(p_notes,''),1000)
  where id=p_issue_id and unit_id=v_unit and status='ISSUED';
  if not found then raise exception 'Issued item not found or already returned' using errcode='P0002'; end if;
  delete from private.um_inventory_rpc_context where txid=txid_current() and user_id=auth.uid() and action='return';
  return true;
end;
$$;

create or replace function public.um_review_leave(p_request_id uuid,p_decision public.um_leave_status,p_note text default '')
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid;
begin
  v_unit:=private.current_unit_id();
  if p_decision not in ('APPROVED','REJECTED') then raise exception 'Decision must be APPROVED or REJECTED' using errcode='22023'; end if;
  if v_unit is null or not (private.um_has_role_in_unit(auth.uid(),v_unit,'admin') or private.um_has_role_in_unit(auth.uid(),v_unit,'officer')) then raise exception 'Only officers/admins may review leave' using errcode='42501'; end if;
  update public.um_leave_requests set status=p_decision,reviewed_by=auth.uid(),reviewed_at=now(),review_note=left(coalesce(p_note,''),1000),updated_at=now()
  where id=p_request_id and unit_id=v_unit and status='PENDING';
  if not found then raise exception 'Pending leave request not found' using errcode='P0002'; end if;
  return true;
end;
$$;

create or replace function public.um_certificate_eligibility(p_cadet_id uuid,p_level public.um_certificate_level)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_threshold numeric; v_leave boolean; v_att numeric; v_total integer; v_done integer;
begin
  v_unit:=private.current_unit_id();
  if v_unit is null or not exists(select 1 from public.um_cadets c where c.id=p_cadet_id and c.unit_id=v_unit) then raise exception 'Cadet not found in current unit' using errcode='P0002'; end if;
  select s.attendance_threshold,s.leave_counts_as_present into v_threshold,v_leave from public.um_settings s where s.unit_id=v_unit limit 1;
  v_threshold:=coalesce(v_threshold,75);
  select case when count(*)=0 then 100 else round(100.0*count(*) filter(where a.status in ('PRESENT','LATE') or (v_leave and a.status='LEAVE'))/count(*),1) end
  into v_att from public.um_attendance a join public.um_parades p on p.id=a.parade_id and p.unit_id=a.unit_id
  where a.unit_id=v_unit and a.cadet_id=p_cadet_id and p.status in ('APPROVED','COMPLETED');
  select count(*) into v_total from public.um_syllabus_items s where s.unit_id=v_unit and s.certificate_level=p_level and s.is_active;
  select count(*) into v_done from public.um_cadet_syllabus_progress p join public.um_syllabus_items s on s.id=p.syllabus_item_id and s.unit_id=p.unit_id
  where p.unit_id=v_unit and p.cadet_id=p_cadet_id and s.certificate_level=p_level and s.is_active and p.completed_on is not null and p.signed_off_by is not null;
  return jsonb_build_object('cadet_id',p_cadet_id,'level',p_level,'attendance_percentage',coalesce(v_att,100),'attendance_threshold',v_threshold,'attendance_met',coalesce(v_att,100)>=v_threshold,'syllabus_total',v_total,'syllabus_signed_off',v_done,'syllabus_complete',v_total>0 and v_done=v_total,'eligible',coalesce(v_att,100)>=v_threshold and v_total>0 and v_done=v_total);
end;
$$;

create or replace function public.um_issue_certificate(p_cadet_id uuid,p_level public.um_certificate_level,p_certificate_number text,p_issued_on date default current_date,p_notes text default '')
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_elig jsonb; v_id uuid;
begin
  v_unit:=private.current_unit_id();
  if v_unit is null or not (private.um_has_role_in_unit(auth.uid(),v_unit,'admin') or private.um_has_role_in_unit(auth.uid(),v_unit,'officer')) then raise exception 'Only officers/admins may issue certificates' using errcode='42501'; end if;
  v_elig:=public.um_certificate_eligibility(p_cadet_id,p_level);
  if not coalesce((v_elig->>'eligible')::boolean,false) then raise exception 'Cadet is not eligible: %',v_elig using errcode='23514'; end if;
  insert into public.um_certificates(unit_id,cadet_id,certificate_level,certificate_number,issued_on,issued_by,notes)
  values(v_unit,p_cadet_id,p_level,trim(p_certificate_number),p_issued_on,auth.uid(),left(coalesce(p_notes,''),1000)) returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.um_generate_parade_series(text,public.um_parade_type,text,text,smallint,date,date,time,time,uuid[],smallint[]) to authenticated;
grant execute on function public.um_save_attendance(uuid,jsonb) to authenticated;
grant execute on function public.um_issue_item(uuid,uuid,integer,date) to authenticated;
grant execute on function public.um_return_item(uuid,public.um_inventory_condition,text) to authenticated;
grant execute on function public.um_review_leave(uuid,public.um_leave_status,text) to authenticated;
grant execute on function public.um_certificate_eligibility(uuid,public.um_certificate_level) to authenticated;
grant execute on function public.um_issue_certificate(uuid,public.um_certificate_level,text,date,text) to authenticated;
revoke all on function public.um_generate_parade_series(text,public.um_parade_type,text,text,smallint,date,date,time,time,uuid[],smallint[]) from public,anon;
revoke all on function public.um_save_attendance(uuid,jsonb) from public,anon;
revoke all on function public.um_issue_item(uuid,uuid,integer,date) from public,anon;
revoke all on function public.um_return_item(uuid,public.um_inventory_condition,text) from public,anon;
revoke all on function public.um_review_leave(uuid,public.um_leave_status,text) from public,anon;
revoke all on function public.um_certificate_eligibility(uuid,public.um_certificate_level) from public,anon;
revoke all on function public.um_issue_certificate(uuid,public.um_certificate_level,text,date,text) from public,anon;
