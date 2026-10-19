-- Extend the fictional seed pack with fitness, kit, leave and camp records.
create or replace function public.um_seed_demo()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_flights uuid[]; v_flight uuid; v_cadet uuid; v_parade uuid; v_date date; i integer; j integer; v_created integer := 0; v_parades integer := 0; v_attendance integer := 0; v_code text; v_name text;
begin
  v_unit:=private.current_unit_id();
  if v_unit is null or not private.um_has_role_in_unit(auth.uid(),v_unit,'admin') then
    raise exception 'Only a unit admin can seed demo records' using errcode='42501';
  end if;

  insert into public.um_settings(unit_id,attendance_threshold,leave_counts_as_present,flight_label,settings,updated_by)
  values(v_unit,75,true,'Flight','{}'::jsonb,auth.uid())
  on conflict(unit_id) do nothing;

  for i in 1..3 loop
    v_code:=case i when 1 then 'ALPHA' when 2 then 'BRAVO' else 'CHARLIE' end;
    v_name:=case i when 1 then 'Alpha Flight' when 2 then 'Bravo Flight' else 'Charlie Flight' end;
    insert into public.um_flights(unit_id,code,name,description)
    values(v_unit,v_code,v_name,'Demo flight for NCC Unit Manager')
    on conflict(unit_id,code) do update set name=excluded.name
    returning id into v_flight;
    v_flights[i]:=v_flight;
  end loop;

  for i in 1..30 loop
    v_flight:=v_flights[((i-1)%3)+1];
    insert into public.um_cadets(unit_id,flight_id,regimental_no,full_name,wing,year_of_training,rank,status)
    values(v_unit,v_flight,format('DEMO-%03s',i),format('Demo Cadet %s',lpad(i::text,2,'0')),'AIR',((i-1)%3)+1,
      case when i<=3 then 'Senior' else 'Cadet' end,'ACTIVE')
    on conflict(unit_id,regimental_no) do update set flight_id=excluded.flight_id,full_name=excluded.full_name
    returning id into v_cadet;
    v_created:=v_created+1;
  end loop;

  insert into public.um_inventory_items(unit_id,item_code,name,description,total_qty,condition,reorder_level,is_active)
  values
    (v_unit,'DEMO-DRILL-RIFLE','Drill rifle','Training equipment only',24,'SERVICEABLE',5,true),
    (v_unit,'DEMO-BELT','Ceremonial belt','Demo kit inventory',18,'SERVICEABLE',4,true),
    (v_unit,'DEMO-BOOT','Parade boot pair','Demo kit inventory',16,'NEEDS_REPAIR',4,true)
  on conflict(unit_id,item_code) do nothing;

  insert into public.um_fitness_metrics(unit_id,code,name,unit_label,higher_is_better,is_active)
  values
    (v_unit,'DEMO-RUN','1.6 km run','seconds',false,true),
    (v_unit,'DEMO-PUSHUP','Push-ups','repetitions',true,true),
    (v_unit,'DEMO-SITUP','Sit-ups','repetitions',true,true)
  on conflict(unit_id,code) do nothing;

  insert into public.um_syllabus_items(unit_id,certificate_level,subject,topic,sequence_no,is_active)
  values
    (v_unit,'A','NCC Basics','NCC organisation and ethos',1,true),
    (v_unit,'A','Drill','Attention, stand at ease and turns',2,true),
    (v_unit,'A','Air Wing','Basic aviation knowledge',3,true),
    (v_unit,'B','Air Wing','Aeromodelling fundamentals',1,true),
    (v_unit,'B','Navigation','Map reading and navigation',2,true),
    (v_unit,'B','Leadership','Command and leadership',3,true),
    (v_unit,'C','Air Wing','Air power and aerospace systems',1,true),
    (v_unit,'C','Leadership','Advanced leadership',2,true)
  on conflict(unit_id,certificate_level,subject,topic) do nothing;

  for i in 1..8 loop
    v_date:=current_date - (i*7);
    insert into public.um_parades(unit_id,created_by,title,parade_date,starts_at,ends_at,venue,parade_type,description,target_flights,target_years,status,approved_by,approved_at,completed_at)
    values(v_unit,auth.uid(),format('Demo Training Parade %s',9-i),v_date,'06:00','08:00','Unit Parade Ground','DRILL','Fictional sample record',v_flights,array[1,2,3]::smallint[],'COMPLETED',auth.uid(),now(),now())
    returning id into v_parade;
    v_parades:=v_parades+1;
    for j in 1..30 loop
      select c.id into v_cadet from public.um_cadets c where c.unit_id=v_unit and c.regimental_no=format('DEMO-%03s',j);
      insert into public.um_attendance(unit_id,parade_id,cadet_id,status,notes,marked_by)
      values(v_unit,v_parade,v_cadet,
        case when (j+i)%11=0 then 'ABSENT'::public.um_attendance_status when (j+i)%7=0 then 'LATE'::public.um_attendance_status else 'PRESENT'::public.um_attendance_status end,
        'Fictional demo attendance',auth.uid())
      on conflict(parade_id,cadet_id) do nothing;
      v_attendance:=v_attendance+1;
    end loop;
  end loop;

  -- Fitness test history and individual results.
  for i in 1..3 loop
    select id into v_flight from public.um_fitness_metrics
      where unit_id=v_unit and code=case i when 1 then 'DEMO-RUN' when 2 then 'DEMO-PUSHUP' else 'DEMO-SITUP' end;
    insert into public.um_fitness_tests(unit_id,test_date,title,metric_id,recorded_by,notes)
    values(v_unit,current_date-(i*10),case i when 1 then 'Demo 1.6 km assessment' when 2 then 'Demo push-up assessment' else 'Demo sit-up assessment' end,v_flight,auth.uid(),'Fictional sample fitness record')
    returning id into v_parade;
    for j in 1..30 loop
      select c.id into v_cadet from public.um_cadets c where c.unit_id=v_unit and c.regimental_no=format('DEMO-%03s',j);
      insert into public.um_fitness_results(unit_id,test_id,cadet_id,result_value,result_status,notes)
      values(v_unit,v_parade,v_cadet,
        case i when 1 then 500+(j*17) when 2 then 8+(j%24) else 10+(j%28) end,
        case when j%9=0 then 'BELOW_STANDARD' when j%5=0 then 'EXCELLENT' else 'PASS' end,
        'Fictional sample result');
    end loop;
  end loop;

  -- A small number of issued kit records demonstrates outstanding stock.
  insert into private.um_inventory_rpc_context(txid,user_id,action)
  values(txid_current(),auth.uid(),'issue') on conflict do nothing;
  insert into public.um_inventory_issues(unit_id,item_id,cadet_id,qty,due_date,status,issued_by,issued_at,return_notes)
  select v_unit,i.id,c.id,1,current_date+14,'ISSUED',auth.uid(),now(),'Fictional demo issue'
  from public.um_inventory_items i
  join public.um_cadets c on c.unit_id=i.unit_id
  where i.unit_id=v_unit and i.item_code='DEMO-BELT' and c.regimental_no in ('DEMO-001','DEMO-002','DEMO-003');
  delete from private.um_inventory_rpc_context where txid=txid_current() and user_id=auth.uid() and action='issue';

  -- One pending leave request illustrates the review queue.
  insert into public.um_leave_requests(unit_id,cadet_id,starts_on,ends_on,reason,status)
  select v_unit,c.id,current_date+3,current_date+4,'Fictional demo leave request','PENDING'
  from public.um_cadets c where c.unit_id=v_unit and c.regimental_no='DEMO-006'
  and not exists(select 1 from public.um_leave_requests l where l.unit_id=v_unit and l.cadet_id=c.id and l.reason='Fictional demo leave request');

  insert into public.um_camps(unit_id,name,camp_type,venue,starts_on,ends_on,description,status,created_by)
  select v_unit,'Demo Air Wing Training Camp','TRAINING','Unit Training Area',current_date+21,current_date+23,'Fictional sample camp','PLANNED',auth.uid()
  where not exists(select 1 from public.um_camps c where c.unit_id=v_unit and c.name='Demo Air Wing Training Camp');

  insert into public.um_notifications(unit_id,recipient_id,title,message,notification_type)
  select v_unit,auth.uid(),'Demo data created','Fictional training records are ready for review.','SYSTEM'
  where not exists(select 1 from public.um_notifications n where n.unit_id=v_unit and n.recipient_id=auth.uid() and n.title='Demo data created');

  return jsonb_build_object('unit_id',v_unit,'flights_created_or_updated',3,'cadets_created_or_updated',v_created,'parades_created',v_parades,'attendance_rows_attempted',v_attendance,'demo_data',true);
end;
$$;
grant execute on function public.um_seed_demo() to authenticated;
revoke all on function public.um_seed_demo() from public,anon;
