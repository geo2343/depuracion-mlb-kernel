-- @AnalistaDepuracionRNFI_A V1.2 manual user bridge and finalization hardening.
create table if not exists public.depurnrfi_a_user_authorizations (
  authorization_id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.depurnrfi_a_runs(run_id) on delete cascade,
  user_message_hash text not null,
  source text not null,
  authorization_scope text not null default 'ONE_OUTBOUND_PEER_INTERVENTION',
  allowed_discrepancy_id text,
  test_only boolean not null default false,
  consumed boolean not null default false,
  consumed_at timestamptz,
  consumed_by_event_id uuid,
  revoked_at timestamptz,
  revoked_reason text,
  metadata jsonb not null default '{}'::jsonb,
  granted_at timestamptz not null default clock_timestamp(),
  unique(run_id,user_message_hash)
);
alter table public.depurnrfi_a_user_authorizations enable row level security;
revoke all on public.depurnrfi_a_user_authorizations from anon, authenticated;
grant select,insert,update,delete on public.depurnrfi_a_user_authorizations to service_role;
alter table public.depurnrfi_a_dialogue_events add column if not exists authorization_id uuid references public.depurnrfi_a_user_authorizations(authorization_id);

create or replace function public.depurnrfi_a_register_user_authorization(p_run uuid,p_user_message_hash text,p_source text,p_allowed_discrepancy_id text,p_metadata jsonb,p_expected_state integer)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_run record; v_id uuid; v_test boolean;
begin
  select * into v_run from depurnrfi_a_runs where run_id=p_run for update;
  if not found then raise exception 'RUN_NOT_FOUND'; end if;
  if v_run.state_version<>p_expected_state then raise exception 'STALE_STATE'; end if;
  if v_run.status<>'DIALOGUE_WAITING_USER_AUTHORIZATION' then raise exception 'NOT_WAITING_USER_AUTHORIZATION'; end if;
  if p_user_message_hash is null or p_user_message_hash !~ '^[0-9a-fA-F]{64}$' then raise exception 'USER_MESSAGE_HASH_REQUIRED_SHA256'; end if;
  v_test:=coalesce(v_run.test_mode,false);
  if v_test then
    if p_source not in ('CHAT_USER_EXPLICIT','TEST_FIXTURE_EXPLICIT') then raise exception 'INVALID_AUTHORIZATION_SOURCE'; end if;
  else
    if p_source<>'CHAT_USER_EXPLICIT' then raise exception 'REAL_RUN_REQUIRES_CHAT_USER_EXPLICIT'; end if;
  end if;
  insert into depurnrfi_a_user_authorizations(run_id,user_message_hash,source,allowed_discrepancy_id,test_only,metadata)
  values(p_run,lower(p_user_message_hash),p_source,p_allowed_discrepancy_id,v_test,coalesce(p_metadata,'{}'::jsonb)) returning authorization_id into v_id;
  perform depurnrfi_a_append_event(p_run,'USER_AUTHORIZATION_REGISTERED',jsonb_build_object('authorization_id',v_id,'source',p_source,'allowed_discrepancy_id',p_allowed_discrepancy_id,'test_only',v_test));
  return jsonb_build_object('status','FRESH','authorization_id',v_id,'run_id',p_run,'state_version',p_expected_state,'single_use',true);
exception when unique_violation then raise exception 'USER_AUTHORIZATION_MESSAGE_ALREADY_USED';
end $$;
revoke all on function public.depurnrfi_a_register_user_authorization(uuid,text,text,text,jsonb,integer) from public,anon,authenticated;
grant execute on function public.depurnrfi_a_register_user_authorization(uuid,text,text,text,jsonb,integer) to service_role;

create or replace function public.depurnrfi_a_receive_counterpart_report(p_run uuid,p_payload jsonb,p_declared_sha256 text,p_expected_state integer)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_run record; v_sha text; v_id uuid;
begin
 select * into v_run from depurnrfi_a_runs where run_id=p_run for update;
 if not found then raise exception 'RUN_NOT_FOUND'; end if;
 if v_run.state_version<>p_expected_state then raise exception 'STALE_STATE'; end if;
 if v_run.status<>'WAITING_FOR_COUNTERPART' then raise exception 'NOT_WAITING_FOR_COUNTERPART'; end if;
 if p_payload->>'producer_agent_id'<>'@AnalistaDepuracionRNFI_D' or p_payload->>'report_type'<>'FINAL_DIALOGUE_REPORT_D' then raise exception 'WRONG_COUNTERPART_IDENTITY'; end if;
 if p_payload->>'upstream_packet_hash' is distinct from v_run.upstream_packet_hash then raise exception 'COUNTERPART_DIFFERENT_UPSTREAM_PACKET'; end if;
 if v_run.test_mode and (coalesce((p_payload->>'test_only')::boolean,false)<>true or coalesce((p_payload->>'synthetic_fixture')::boolean,false)<>true) then raise exception 'TEST_COUNTERPART_FLAGS_REQUIRED'; end if;
 if not v_run.test_mode and (coalesce((p_payload->>'test_only')::boolean,false)=true or coalesce((p_payload->>'synthetic_fixture')::boolean,false)=true) then raise exception 'SYNTHETIC_COUNTERPART_FORBIDDEN_REAL'; end if;
 v_sha:=depurnrfi_a_hash_json(p_payload);
 if p_declared_sha256 is distinct from v_sha then raise exception 'COUNTERPART_HASH_MISMATCH'; end if;
 insert into depurnrfi_a_counterpart_reports(run_id,producer_agent_id,report_type,producer_version,upstream_packet_hash,payload,declared_sha256,recomputed_sha256,test_only,synthetic_fixture,verified)
 values(p_run,'@AnalistaDepuracionRNFI_D','FINAL_DIALOGUE_REPORT_D',p_payload->>'producer_version',v_run.upstream_packet_hash,p_payload,p_declared_sha256,v_sha,v_run.test_mode,v_run.test_mode,true) returning counterpart_report_id into v_id;
 update depurnrfi_a_runs set status='DIALOGUE_WAITING_USER_AUTHORIZATION',state_version=state_version+1,updated_at=now() where run_id=p_run;
 perform depurnrfi_a_append_event(p_run,'COUNTERPART_BOUND_WAITING_USER_AUTHORIZATION',jsonb_build_object('counterpart_report_id',v_id,'auto_started',false));
 return jsonb_build_object('status','DIALOGUE_WAITING_USER_AUTHORIZATION','auto_started',false,'counterpart_report_id',v_id,'state_version',p_expected_state+1,'fresh_user_authorization_required',true);
end $$;

create or replace function public.depurnrfi_a_add_dialogue_event(p_run uuid,p_discrepancy_id text,p_turn_no integer,p_actor text,p_resolution text,p_evidence_refs jsonb,p_causal_argument text,p_payload jsonb,p_expected_state integer)
returns uuid language plpgsql security definer set search_path='public' as $$
declare v_state int; v_status text; v_id uuid; v_prior int; v_auth uuid; v_authrow record;
begin
 select state_version,status into v_state,v_status from depurnrfi_a_runs where run_id=p_run for update;
 if v_state is null then raise exception 'RUN_NOT_FOUND'; end if;
 if v_state<>p_expected_state then raise exception 'STALE_STATE'; end if;
 if p_turn_no<1 or p_turn_no>3 then raise exception 'DIALOGUE_TURN_LIMIT_EXCEEDED'; end if;
 if p_actor not in ('@AnalistaDepuracionRNFI_A','@AnalistaDepuracionRNFI_D') then raise exception 'INVALID_DIALOGUE_ACTOR'; end if;
 if p_resolution not in ('ACCEPT','PARTIAL_ACCEPT','REBUT','OPEN') then raise exception 'INVALID_DIALOGUE_RESOLUTION'; end if;
 if length(coalesce(p_discrepancy_id,''))<3 then raise exception 'DISCREPANCY_ID_REQUIRED'; end if;
 if length(coalesce(p_causal_argument,''))<60 then raise exception 'CAUSAL_ARGUMENT_TOO_SHORT'; end if;
 if jsonb_typeof(coalesce(p_evidence_refs,'[]'::jsonb))<>'array' then raise exception 'DIALOGUE_EVIDENCE_REFS_MUST_BE_ARRAY'; end if;
 select count(*) into v_prior from depurnrfi_a_dialogue_events where run_id=p_run and discrepancy_id=p_discrepancy_id;
 if v_prior>=3 then raise exception 'DIALOGUE_TURN_LIMIT_EXCEEDED'; end if;
 if p_actor='@AnalistaDepuracionRNFI_A' then
   if v_status<>'DIALOGUE_WAITING_USER_AUTHORIZATION' then raise exception 'FRESH_USER_AUTHORIZATION_REQUIRED'; end if;
   begin v_auth := nullif(p_payload->>'authorization_id','')::uuid; exception when others then raise exception 'VALID_AUTHORIZATION_ID_REQUIRED'; end;
   if v_auth is null then raise exception 'VALID_AUTHORIZATION_ID_REQUIRED'; end if;
   select * into v_authrow from depurnrfi_a_user_authorizations where authorization_id=v_auth for update;
   if not found or v_authrow.run_id<>p_run then raise exception 'AUTHORIZATION_NOT_BOUND_TO_RUN'; end if;
   if v_authrow.consumed or v_authrow.revoked_at is not null then raise exception 'AUTHORIZATION_NOT_FRESH'; end if;
   if v_authrow.allowed_discrepancy_id is not null and v_authrow.allowed_discrepancy_id<>p_discrepancy_id then raise exception 'AUTHORIZATION_WRONG_DISCREPANCY'; end if;
 else
   if v_status<>'DIALOGUE_WAITING_PEER_REPLY' then raise exception 'PEER_REPLY_NOT_EXPECTED'; end if;
 end if;
 insert into depurnrfi_a_dialogue_events(run_id,discrepancy_id,turn_no,actor_agent_id,resolution,evidence_refs,causal_argument,payload,authorization_id)
 values(p_run,p_discrepancy_id,p_turn_no,p_actor,p_resolution,coalesce(p_evidence_refs,'[]'::jsonb),p_causal_argument,coalesce(p_payload,'{}'::jsonb),case when p_actor='@AnalistaDepuracionRNFI_A' then v_auth else null end) returning dialogue_event_id into v_id;
 if p_actor='@AnalistaDepuracionRNFI_A' then
   update depurnrfi_a_user_authorizations set consumed=true,consumed_at=clock_timestamp(),consumed_by_event_id=v_id where authorization_id=v_auth;
   update depurnrfi_a_runs set status='DIALOGUE_WAITING_PEER_REPLY',state_version=state_version+1,updated_at=now() where run_id=p_run;
   perform depurnrfi_a_append_event(p_run,'A_OUTBOUND_AUTHORIZATION_CONSUMED',jsonb_build_object('authorization_id',v_auth,'dialogue_event_id',v_id,'discrepancy_id',p_discrepancy_id));
 else
   update depurnrfi_a_runs set status='DIALOGUE_WAITING_USER_AUTHORIZATION',state_version=state_version+1,updated_at=now() where run_id=p_run;
   perform depurnrfi_a_append_event(p_run,'D_PEER_REPLY_BOUND_WAITING_USER_AUTHORIZATION',jsonb_build_object('dialogue_event_id',v_id,'discrepancy_id',p_discrepancy_id));
 end if;
 return v_id;
end $$;

create or replace function public.depurnrfi_a_finalize_dialogue(p_run uuid,p_payload jsonb,p_expected_state integer)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_run record; v_missing int; v_art uuid; v_sha text; v_rev int; v_consensus boolean;
begin
 select * into v_run from depurnrfi_a_runs where run_id=p_run for update;
 if not found then raise exception 'RUN_NOT_FOUND'; end if;
 if v_run.state_version<>p_expected_state then raise exception 'STALE_STATE'; end if;
 if v_run.status<>'DIALOGUE_CLOSED_BY_D' then raise exception 'D_MUST_CLOSE_FIRST'; end if;
 if coalesce((v_run.metadata->>'d_closed_first')::boolean,false)<>true then raise exception 'D_MUST_CLOSE_FIRST'; end if;
 select count(*) into v_missing from depurnrfi_a_requirement_catalog c left join depurnrfi_a_requirement_state s on s.requirement_id=c.requirement_id and s.run_id=p_run where c.phase_code='DIALOGUE' and c.binding=true and s.status is distinct from 'COMPLETE';
 if v_missing>0 then raise exception 'DIALOGUE_REQUIREMENTS_INCOMPLETE'; end if;
 if not(p_payload ?& array['candidates','reserves','rejected','candidate_not_bet','consensus_reached','unresolved_material_disagreements']) then raise exception 'FINAL_DIALOGUE_PAYLOAD_INCOMPLETE'; end if;
 if jsonb_typeof(p_payload->'candidates')<>'array' or jsonb_array_length(p_payload->'candidates')>4 then raise exception 'CANDIDATE_MAX_EXCEEDED'; end if;
 if coalesce((p_payload->>'candidate_not_bet')::boolean,false)<>true then raise exception 'CANDIDATE_MUST_NOT_BE_BET'; end if;
 v_consensus:=coalesce((p_payload->>'consensus_reached')::boolean,false);
 if not v_consensus and (p_payload->'unresolved_material_disagreements' is null or jsonb_typeof(p_payload->'unresolved_material_disagreements')<>'array' or jsonb_array_length(p_payload->'unresolved_material_disagreements')=0) then raise exception 'UNRESOLVED_DISAGREEMENT_MUST_BE_EXPLICIT'; end if;
 select coalesce(max(revision),0)+1 into v_rev from depurnrfi_a_phase_artifacts where run_id=p_run and phase_code='DIALOGUE';
 v_sha:=depurnrfi_a_hash_json(p_payload);
 insert into depurnrfi_a_phase_artifacts(run_id,phase_code,revision,artifact_type,payload,sha256,readback_verified) values(p_run,'DIALOGUE',v_rev,'FINAL_DEPURATION_SET_POST_DIALOGUE',p_payload,v_sha,true) returning artifact_id into v_art;
 update depurnrfi_a_runs set status='COMPLETE',state_version=state_version+1,current_phase='DIALOGUE',candidate_count=jsonb_array_length(p_payload->'candidates'),final_artifact_sha256=v_sha,metadata=metadata||jsonb_build_object('consensus_reached',v_consensus,'unresolved_disagreement_preserved',not v_consensus,'manual_bridge_enforced',true),updated_at=now() where run_id=p_run;
 perform depurnrfi_a_append_event(p_run,'RUN_COMPLETED',jsonb_build_object('final_sha256',v_sha,'candidate_count',jsonb_array_length(p_payload->'candidates'),'consensus_reached',v_consensus,'manual_bridge_enforced',true));
 return jsonb_build_object('status','COMPLETE','artifact_id',v_art,'artifact_sha256',v_sha,'state_version',p_expected_state+1,'consensus_required',false,'manual_bridge_enforced',true);
end $$;