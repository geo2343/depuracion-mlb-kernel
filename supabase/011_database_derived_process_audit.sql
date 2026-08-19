-- Kernel 0.3: process audit is derived from physical database state.
-- Caller supplied audit_status / derived_by has no authority for Agent 1.1 runs.

create or replace function public.dep_mlb_derive_process_audit()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare av text; kv text; p_run text; p_game text; p_frozen timestamptz; p_hash text; p_drive_file text; p_drive_hash text;
declare tool_count integer; evidence_count integer; claim_count integer; phase_artifact_count integer; phase_pass_count integer; drive_ok boolean;
begin
  select r.agent_version,r.kernel_version into av,kv from public.dep_mlb_runs r where r.run_id=new.run_id;
  if av='DEP-MLB-AGENT-1.1' or kv='DEP-MLB-KERNEL-0.3-AUTONOMOUS' then
    select run_id,game_id,frozen_at,packet_hash,drive_file_id,drive_hash into p_run,p_game,p_frozen,p_hash,p_drive_file,p_drive_hash
    from public.dep_mlb_game_packets where packet_id=new.packet_id;
    if not found or p_run<>new.run_id or p_game<>new.game_id then raise exception 'DEP_MLB_AUDIT_PACKET_RUN_GAME_MISMATCH'; end if;
    select count(*) into tool_count from public.dep_mlb_tool_events where run_id=new.run_id and game_id=new.game_id and success=true;
    select count(*) into evidence_count from public.dep_mlb_evidence where run_id=new.run_id and game_id=new.game_id;
    select count(*) into claim_count from public.dep_mlb_claims where run_id=new.run_id and game_id=new.game_id;
    select count(distinct phase_code) into phase_artifact_count from public.dep_mlb_phase_artifacts where run_id=new.run_id and game_id=new.game_id and phase_code in ('F2','F3','F4','F5','F6','F7','F8','F9');
    select count(*) into phase_pass_count from public.dep_mlb_phase_state where run_id=new.run_id and phase_order between 0 and 9 and state='PASS';
    select exists(select 1 from public.dep_mlb_drive_artifacts d where d.run_id=new.run_id and d.game_id=new.game_id and d.drive_file_id=p_drive_file and d.content_hash=p_drive_hash and d.verified_readback=true and d.verification_source='GOOGLE_DRIVE_CONNECTOR') into drive_ok;
    new.checks:=jsonb_build_object('derived_from_database_state',true,'tool_events_success',tool_count,'evidence_count',evidence_count,'claims_count',claim_count,'required_game_phase_artifacts',phase_artifact_count,'f0_to_f9_pass_count',phase_pass_count,'packet_frozen',p_frozen is not null,'packet_hash_present',p_hash is not null and length(p_hash)>=32,'drive_readback_verified',drive_ok,'same_run_game_packet',p_run=new.run_id and p_game=new.game_id);
    new.audit_status:=case when tool_count>=1 and evidence_count>=1 and claim_count>=1 and phase_artifact_count=8 and phase_pass_count=10 and p_frozen is not null and p_hash is not null and length(p_hash)>=32 and drive_ok then 'PASS' else 'FAIL' end;
    new.derived_by:='DATABASE_CONTROL';
    new.derived_at:=now();
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_derive_process_audit_guard on public.dep_mlb_process_audits;
create trigger dep_mlb_derive_process_audit_guard before insert or update on public.dep_mlb_process_audits
for each row execute function public.dep_mlb_derive_process_audit();
