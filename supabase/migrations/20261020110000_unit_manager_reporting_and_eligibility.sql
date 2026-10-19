-- Correct role scope for certificate eligibility and expose an RLS-respecting attendance summary.
create or replace function public.um_certificate_eligibility(p_cadet_id uuid,p_level public.um_certificate_level)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, private
as $$
declare v_unit uuid; v_threshold numeric; v_leave boolean; v_att numeric; v_total integer; v_done integer; v_role public.um_role; v_flight uuid;
begin
  v_unit:=private.current_unit_id();
  select r.role into v_role from public.um_user_roles r where r.user_id=auth.uid() and r.unit_id=v_unit;
  if v_unit is null or v_role is null then raise exception 'No active role in current unit' using errcode='42501'; end if;
  select c.flight_id into v_flight from public.um_cadets c where c.id=p_cadet_id and c.unit_id=v_unit;
  if not found then raise exception 'Cadet not found in current unit' using errcode='P0002'; end if;
  if v_role='cadet' and not exists(select 1 from public.um_cadets c where c.id=p_cadet_id and c.unit_id=v_unit and c.user_id=auth.uid()) then
    raise exception 'Cadets may only check their own certificate eligibility' using errcode='42501';
  end if;
  if v_role='senior' and v_flight is distinct from private.current_flight_id() then
    raise exception 'Seniors may only check cadets in their own flight' using errcode='42501';
  end if;
  select s.attendance_threshold,s.leave_counts_as_present into v_threshold,v_leave from public.um_settings s where s.unit_id=v_unit limit 1;
  v_threshold:=coalesce(v_threshold,75);
  select case when count(*)=0 then 100 else round(100.0*count(*) filter(where a.status in ('PRESENT','LATE') or (v_leave and a.status='LEAVE'))/count(*),1) end
  into v_att
  from public.um_parades p
  left join public.um_attendance a on a.parade_id=p.id and a.unit_id=p.unit_id and a.cadet_id=p_cadet_id
  where p.unit_id=v_unit and p.status in ('APPROVED','COMPLETED')
    and (cardinality(p.target_flights)=0 or v_flight=any(p.target_flights))
    and (cardinality(p.target_years)=0 or exists(select 1 from public.um_cadets c where c.id=p_cadet_id and c.year_of_training=any(p.target_years)));
  select count(*) into v_total from public.um_syllabus_items s where s.unit_id=v_unit and s.certificate_level=p_level and s.is_active;
  select count(*) into v_done from public.um_cadet_syllabus_progress p join public.um_syllabus_items s on s.id=p.syllabus_item_id and s.unit_id=p.unit_id
  where p.unit_id=v_unit and p.cadet_id=p_cadet_id and s.certificate_level=p_level and s.is_active and p.completed_on is not null and p.signed_off_by is not null;
  return jsonb_build_object('cadet_id',p_cadet_id,'level',p_level,'attendance_percentage',coalesce(v_att,100),'attendance_threshold',v_threshold,'attendance_met',coalesce(v_att,100)>=v_threshold,'syllabus_total',v_total,'syllabus_signed_off',v_done,'syllabus_complete',v_total>0 and v_done=v_total,'eligible',coalesce(v_att,100)>=v_threshold and v_total>0 and v_done=v_total);
end;
$$;
revoke all on function public.um_certificate_eligibility(uuid,public.um_certificate_level) from public,anon;
grant execute on function public.um_certificate_eligibility(uuid,public.um_certificate_level) to authenticated;

create or replace view public.um_attendance_summary
with (security_invoker=true)
as
select
  c.unit_id,
  c.id as cadet_id,
  c.regimental_no,
  c.full_name,
  c.flight_id,
  c.year_of_training,
  count(p.id)::integer as parades_held,
  count(*) filter(where a.status in ('PRESENT','LATE') or (coalesce(s.leave_counts_as_present,true) and a.status='LEAVE'))::integer as attended,
  case when count(p.id)=0 then 100::numeric
       else round(100.0*count(*) filter(where a.status in ('PRESENT','LATE') or (coalesce(s.leave_counts_as_present,true) and a.status='LEAVE'))/count(p.id),1)
  end as attendance_percentage,
  coalesce(s.attendance_threshold,75) as attendance_threshold,
  case when count(p.id)=0 then false
       else round(100.0*count(*) filter(where a.status in ('PRESENT','LATE') or (coalesce(s.leave_counts_as_present,true) and a.status='LEAVE'))/count(p.id),1) < coalesce(s.attendance_threshold,75)
  end as below_threshold
from public.um_cadets c
left join public.um_parades p on p.unit_id=c.unit_id and p.status in ('APPROVED','COMPLETED')
  and (cardinality(p.target_flights)=0 or c.flight_id=any(p.target_flights))
  and (cardinality(p.target_years)=0 or c.year_of_training=any(p.target_years))
left join public.um_attendance a on a.unit_id=c.unit_id and a.parade_id=p.id and a.cadet_id=c.id
left join public.um_settings s on s.unit_id=c.unit_id
group by c.unit_id,c.id,c.regimental_no,c.full_name,c.flight_id,c.year_of_training,s.attendance_threshold,s.leave_counts_as_present;

grant select on public.um_attendance_summary to authenticated;
