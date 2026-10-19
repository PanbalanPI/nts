-- Do not expose a scheduling workflow for weapon training in this application.
create or replace function private.um_reject_weapon_training()
returns trigger language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.parade_type = 'WEAPON_TRAINING' then
    raise exception 'This application does not schedule weapon-training activities.' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function private.um_reject_weapon_training() from public,anon,authenticated;
drop trigger if exists um_no_weapon_training_parades on public.um_parades;
create trigger um_no_weapon_training_parades before insert or update of parade_type on public.um_parades
for each row execute function private.um_reject_weapon_training();
drop trigger if exists um_no_weapon_training_series on public.um_parade_series;
create trigger um_no_weapon_training_series before insert or update of parade_type on public.um_parade_series
for each row execute function private.um_reject_weapon_training();
