-- Regimental-number login and independent rank/role data.
begin;
alter table public.um_profiles
  add column if not exists regimental_no text,
  add column if not exists rank_title text not null default 'Cadet';
update public.um_profiles p
set regimental_no=c.regimental_no, rank_title=coalesce(nullif(p.rank_title,''),c.rank,'Cadet')
from public.um_cadets c
where c.user_id=p.user_id and c.unit_id=p.unit_id and p.regimental_no is null;
do $$
begin
  if exists(select lower(regimental_no) from public.um_profiles where regimental_no is not null group by lower(regimental_no) having count(*)>1) then
    raise exception 'Duplicate regimental numbers exist; resolve them before migration.';
  end if;
  if exists(select 1 from public.um_profiles p join auth.users u on lower(u.email)=lower(p.regimental_no)||'@unit.local' and u.id<>p.user_id where p.regimental_no is not null) then
    raise exception 'Regimental login email collision; resolve it before migration.';
  end if;
end $$;
create unique index if not exists um_profiles_regimental_no_lower_uidx on public.um_profiles(lower(regimental_no)) where regimental_no is not null;
update auth.users u set email=lower(p.regimental_no)||'@unit.local',email_confirmed_at=coalesce(u.email_confirmed_at,now()),updated_at=now()
from public.um_profiles p where p.user_id=u.id and p.regimental_no is not null and u.email is distinct from lower(p.regimental_no)||'@unit.local';
update public.um_profiles p set email=lower(p.regimental_no)||'@unit.local',updated_at=now()
where p.regimental_no is not null and p.email is distinct from lower(p.regimental_no)||'@unit.local';
comment on column public.um_profiles.regimental_no is 'Unique login identifier; Auth email alias is regimental_no@unit.local.';
comment on column public.um_profiles.rank_title is 'Rank/appointment label independent of application permissions.';
revoke insert,update,delete on public.um_user_roles from anon,authenticated;
grant select on public.um_user_roles to authenticated;
grant all on public.um_user_roles to service_role;
commit;
