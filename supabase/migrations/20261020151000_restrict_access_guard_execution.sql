-- Trigger functions should not be directly callable through the PostgREST RPC endpoint.
revoke all on function public.um_guard_access_level() from public, anon, authenticated;
grant execute on function public.um_guard_access_level() to service_role;

-- The transactional review and delegation functions are callable only by the trusted Edge Function.
revoke all on function public.um_review_unit_registration(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.um_review_unit_registration(uuid, text, text, uuid) to service_role;
revoke all on function public.um_set_unit_admin_access(uuid, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.um_set_unit_admin_access(uuid, uuid, boolean, text) to service_role;
