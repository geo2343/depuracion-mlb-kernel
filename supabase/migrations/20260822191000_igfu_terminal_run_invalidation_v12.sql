create or replace function public.igfu_terminal_invalidate_run(
  p_run_id uuid,
  p_reason_code text,
  p_reason text,
  p_expected_state_version bigint,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
  prior record;
  newver bigint;
  payload jsonb;
begin
  if coalesce(length(btrim(p_idempotency_key)),0) < 8 then raise exception 'IGFU_IDEMPOTENCY_KEY_REQUIRED'; end if;
  if p_reason_code not in ('TEMPORAL_CAPTURE_MISSED','SOURCE_WINDOW_LOST','CONTRACT_VIOLATION','CONTAMINATED_SNAPSHOT','OPERATOR_ABORT') then raise exception 'IGFU_INVALID_TERMINAL_REASON_CODE'; end if;
  if coalesce(length(btrim(p_reason)),0) < 24 then raise exception 'IGFU_TERMINAL_REASON_DETAIL_REQUIRED'; end if;

  select * into prior from public.investigadorglobal_fullunder_command_envelopes where idempotency_key=p_idempotency_key;
  if found then
    select * into r from public.investigadorglobal_fullunder_runs where run_id=p_run_id;
    if not found then raise exception 'IGFU_RUN_NOT_FOUND'; end if;
    return jsonb_build_object('run_id',p_run_id,'status',r.status,'state_version',r.state_version,'idempotent_replay',true);
  end if;

  select * into r from public.investigadorglobal_fullunder_runs where run_id=p_run_id for update;
  if not found then raise exception 'IGFU_RUN_NOT_FOUND'; end if;
  if r.state_version<>p_expected_state_version then raise exception 'IGFU_STALE_STATE_VERSION'; end if;
  if r.status in ('INVESTIGATION_COMPLETE','HANDOFF_PREPARED') then raise exception 'IGFU_COMPLETED_RUN_CANNOT_BE_TERMINALLY_INVALIDATED'; end if;
  if exists(select 1 from public.investigadorglobal_fullunder_handoff_manifests where run_id=p_run_id) then raise exception 'IGFU_HANDOFF_EXISTS_CANNOT_TERMINALLY_INVALIDATE'; end if;

  newver:=r.state_version+1;
  payload:=jsonb_build_object('reason_code',p_reason_code,'reason',p_reason,'previous_status',r.status,'previous_active_phase',r.active_phase,'previous_state_version',r.state_version,'new_state_version',newver,'terminal',true);

  update public.investigadorglobal_fullunder_runs
  set status='INVALIDATED',active_phase=null,state_version=newver,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('terminal_invalidation',payload),updated_at=now()
  where run_id=p_run_id;

  insert into public.investigadorglobal_fullunder_command_envelopes(run_id,action,phase_code,expected_state_version,idempotency_key,payload_sha256,status)
  values(p_run_id,'TERMINAL_INVALIDATE_RUN_V12',r.active_phase,p_expected_state_version,p_idempotency_key,public.igfu_hash_json(payload),'COMMITTED');

  perform public.igfu_append_event(p_run_id,'RUN_TERMINALLY_INVALIDATED',payload);
  return jsonb_build_object('run_id',p_run_id,'status','INVALIDATED','state_version',newver,'reason_code',p_reason_code,'terminal',true);
end
$function$;

revoke all on function public.igfu_terminal_invalidate_run(uuid,text,text,bigint,text) from public, anon, authenticated;
grant execute on function public.igfu_terminal_invalidate_run(uuid,text,text,bigint,text) to service_role;
