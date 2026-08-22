-- Full Under A<->D V1.2 physical handoff verification.
create or replace function public.fuda_receive_counterpart_report(p_run uuid,p_producer text,p_report_type text,p_report_sha text,p_payload jsonb,p_expected_state bigint)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare r record; v_id uuid; v_hash text; v_d record; v_h record; v_source uuid;
begin
 select * into r from public.fullunder_dep_a_runs where run_id=p_run;
 if not found then return jsonb_build_object('outcome','REJECTED','reason','RUN_NOT_FOUND'); end if;
 if r.state_version<>p_expected_state then return jsonb_build_object('outcome','REJECTED','reason','STALE_STATE','actual_state_version',r.state_version); end if;
 if r.status<>'WAITING_FOR_COUNTERPART' or r.current_phase<>'DIALOGUE' then return jsonb_build_object('outcome','REJECTED','reason','WRONG_PHASE'); end if;
 if not r.pre_dialogue_frozen then return jsonb_build_object('outcome','REJECTED','reason','A_NOT_PRE_DIALOGUE_FROZEN'); end if;
 if p_producer<>'@AnalistaDepuracionFullUnder_D' then return jsonb_build_object('outcome','REJECTED','reason','WRONG_COUNTERPART_ALIAS'); end if;
 if p_report_type<>'FINAL_DIALOGUE_REPORT_D' then return jsonb_build_object('outcome','REJECTED','reason','INVALID_COUNTERPART_REPORT_TYPE'); end if;
 if coalesce(p_report_sha,'') !~ '^[0-9a-f]{64}$' then return jsonb_build_object('outcome','REJECTED','reason','INVALID_REPORT_SHA256_FORMAT'); end if;
 v_hash:=public.fuda_hash_json(coalesce(p_payload,'{}'::jsonb)); if v_hash<>p_report_sha then return jsonb_build_object('outcome','REJECTED','reason','COUNTERPART_HASH_MISMATCH','computed_sha256',v_hash); end if;
 if p_payload->>'upstream_packet_sha256' is distinct from r.upstream_packet_sha256 then return jsonb_build_object('outcome','REJECTED','reason','COUNTERPART_DIFFERENT_UPSTREAM_PACKET','expected_upstream_packet_sha256',r.upstream_packet_sha256); end if;
 begin v_source:=(p_payload->>'source_handoff_id')::uuid; exception when others then return jsonb_build_object('outcome','REJECTED','reason','COUNTERPART_PHYSICAL_LINEAGE_MISSING'); end;
 select h.*,dr.agent_id as d_agent_id,dr.agent_version as d_agent_version,dr.upstream_packet_sha256 as d_upstream,dr.pre_dialogue_frozen as d_frozen,dr.test_mode as d_test into v_h from public.fullunder_dep_d_handoffs h join public.fullunder_dep_d_runs dr on dr.run_id=h.run_id where h.handoff_id=v_source;
 if not found then return jsonb_build_object('outcome','REJECTED','reason','D_SOURCE_HANDOFF_NOT_FOUND'); end if;
 if v_h.target_agent_id<>'@AnalistaDepuracionFullUnder_A' or v_h.handoff_type<>'FINAL_DIALOGUE_REPORT_D' then return jsonb_build_object('outcome','REJECTED','reason','D_SOURCE_HANDOFF_WRONG_CONTRACT'); end if;
 if v_h.payload_sha256<>p_report_sha or v_h.payload<>p_payload then return jsonb_build_object('outcome','REJECTED','reason','D_SOURCE_HANDOFF_PAYLOAD_MISMATCH'); end if;
 if v_h.d_agent_id<>'@AnalistaDepuracionFullUnder_D' or v_h.d_upstream<>r.upstream_packet_sha256 or not v_h.d_frozen then return jsonb_build_object('outcome','REJECTED','reason','D_SOURCE_HANDOFF_LINEAGE_INVALID'); end if;
 if r.test_mode then
   if not v_h.d_test or v_h.status<>'PREPARED_TEST_ONLY_DO_NOT_CONSUME' or coalesce(p_payload->>'test_only','false')<>'true' or coalesce(p_payload->>'synthetic_fixture','false')<>'true' or coalesce(p_payload->>'fixture_kind','')<>'SYNTHETIC_D_DIALOGUE_REPORT' then return jsonb_build_object('outcome','REJECTED','reason','TEST_FIXTURE_NOT_EXPLICIT'); end if;
 else
   if v_h.d_test or v_h.status<>'PREPARED_WAITING_FOR_CONSUMER' or coalesce(p_payload->>'test_only','false')='true' or coalesce(p_payload->>'synthetic_fixture','false')='true' then return jsonb_build_object('outcome','REJECTED','reason','SYNTHETIC_COUNTERPART_FORBIDDEN_IN_REAL_RUN'); end if;
   select * into v_d from public.kendel_component_registry where component_id='FULLUNDER_DEPURATION_D'; if not found or v_d.implementation_state not in ('KERNEL_CONNECTED','IMPLEMENTED') or v_d.runtime_state<>'ACTIVE' then return jsonb_build_object('outcome','REJECTED','reason','COUNTERPART_RUNTIME_NOT_PHYSICALLY_READY'); end if;
 end if;
 insert into public.fullunder_dep_a_counterpart_reports(run_id,producer_agent_id,report_type,report_sha256,report_payload,status) values(p_run,p_producer,p_report_type,p_report_sha,p_payload,case when r.test_mode then 'RECEIVED_VERIFIED_SYNTHETIC' else 'RECEIVED_VERIFIED' end) returning counterpart_report_id into v_id;
 update public.fullunder_dep_d_handoffs set acknowledged_by='@AnalistaDepuracionFullUnder_A',peer_receipt_id=v_id::text,acknowledged_at=now(),status=case when r.test_mode then 'ACKNOWLEDGED_TEST_ONLY' else 'DELIVERED_ACKNOWLEDGED' end where handoff_id=v_source;
 update public.fullunder_dep_a_runs set counterpart_report_received=true,status='DIALOGUE_ACTIVE',state_version=state_version+1,updated_at=now() where run_id=p_run;
 perform public.fuda_append_event(p_run,'COUNTERPART_REPORT_RECEIVED','DIALOGUE',r.state_version+1,jsonb_build_object('counterpart_report_id',v_id,'source_handoff_id',v_source,'report_sha256',p_report_sha,'upstream_packet_sha256',r.upstream_packet_sha256,'physical_lineage_verified',true,'test_mode',r.test_mode));
 perform public.fuda_append_event(p_run,'DIALOGUE_AUTO_STARTED','DIALOGUE',r.state_version+1,jsonb_build_object('reason','VALID_COUNTERPART_RECEIVED','consensus_required',false,'unresolved_material_disagreement_allowed',true));
 return jsonb_build_object('outcome','ACCEPTED','counterpart_report_id',v_id,'source_handoff_id',v_source,'verified_sha256',p_report_sha,'upstream_packet_sha256',r.upstream_packet_sha256,'state_version',r.state_version+1,'status','DIALOGUE_ACTIVE','auto_started',true,'physical_lineage_verified',true,'consensus_required',false,'test_mode',r.test_mode);
end $$;

create or replace function public.fuda_receive_d_closing(p_run uuid,p_producer text,p_sha text,p_payload jsonb,p_expected_state bigint)
returns jsonb language plpgsql security definer set search_path='public','extensions' as $$
declare r record; v_id uuid; v_hash text; v_d record; v_parent record; v_h record; v_source uuid;
begin
 select * into r from public.fullunder_dep_a_runs where run_id=p_run;
 if not found then return jsonb_build_object('outcome','REJECTED','reason','RUN_NOT_FOUND'); end if;
 if r.state_version<>p_expected_state then return jsonb_build_object('outcome','REJECTED','reason','STALE_STATE','actual_state_version',r.state_version); end if;
 if r.status<>'DIALOGUE_ACTIVE' then return jsonb_build_object('outcome','REJECTED','reason','DIALOGUE_NOT_ACTIVE'); end if;
 if p_producer<>'@AnalistaDepuracionFullUnder_D' then return jsonb_build_object('outcome','REJECTED','reason','WRONG_COUNTERPART_ALIAS'); end if;
 if coalesce(p_sha,'') !~ '^[0-9a-f]{64}$' then return jsonb_build_object('outcome','REJECTED','reason','INVALID_REPORT_SHA256_FORMAT'); end if;
 v_hash:=public.fuda_hash_json(coalesce(p_payload,'{}'::jsonb)); if v_hash<>p_sha then return jsonb_build_object('outcome','REJECTED','reason','D_CLOSING_HASH_MISMATCH','computed_sha256',v_hash); end if;
 if p_payload->>'upstream_packet_sha256' is distinct from r.upstream_packet_sha256 then return jsonb_build_object('outcome','REJECTED','reason','D_CLOSING_DIFFERENT_UPSTREAM_PACKET','expected_upstream_packet_sha256',r.upstream_packet_sha256); end if;
 select * into v_parent from public.fullunder_dep_a_counterpart_reports where run_id=p_run and producer_agent_id='@AnalistaDepuracionFullUnder_D' and report_type='FINAL_DIALOGUE_REPORT_D' order by received_at desc limit 1;
 if not found then return jsonb_build_object('outcome','REJECTED','reason','D_PARENT_REPORT_MISSING'); end if;
 if p_payload->>'parent_report_sha256' is distinct from v_parent.report_sha256 then return jsonb_build_object('outcome','REJECTED','reason','D_CLOSING_WRONG_PARENT_REPORT','expected_parent_report_sha256',v_parent.report_sha256); end if;
 begin v_source:=(p_payload->>'source_handoff_id')::uuid; exception when others then return jsonb_build_object('outcome','REJECTED','reason','D_CLOSING_PHYSICAL_LINEAGE_MISSING'); end;
 select h.*,dr.agent_id as d_agent_id,dr.agent_version as d_agent_version,dr.upstream_packet_sha256 as d_upstream,dr.test_mode as d_test into v_h from public.fullunder_dep_d_handoffs h join public.fullunder_dep_d_runs dr on dr.run_id=h.run_id where h.handoff_id=v_source;
 if not found then return jsonb_build_object('outcome','REJECTED','reason','D_CLOSING_SOURCE_HANDOFF_NOT_FOUND'); end if;
 if v_h.target_agent_id<>'@AnalistaDepuracionFullUnder_A' or v_h.handoff_type<>'D_DIALOGUE_CLOSING_REPORT' then return jsonb_build_object('outcome','REJECTED','reason','D_CLOSING_SOURCE_WRONG_CONTRACT'); end if;
 if v_h.payload_sha256<>p_sha or v_h.payload<>p_payload or v_h.d_upstream<>r.upstream_packet_sha256 then return jsonb_build_object('outcome','REJECTED','reason','D_CLOSING_SOURCE_PAYLOAD_MISMATCH'); end if;
 if r.test_mode then
   if not v_h.d_test or v_h.status<>'PREPARED_TEST_ONLY_DO_NOT_CONSUME' or coalesce(p_payload->>'test_only','false')<>'true' or coalesce(p_payload->>'synthetic_fixture','false')<>'true' or coalesce(p_payload->>'fixture_kind','')<>'SYNTHETIC_D_DIALOGUE_CLOSING' then return jsonb_build_object('outcome','REJECTED','reason','TEST_FIXTURE_NOT_EXPLICIT'); end if;
 else
   if v_h.d_test or v_h.status<>'PREPARED_WAITING_FOR_CONSUMER' or coalesce(p_payload->>'test_only','false')='true' or coalesce(p_payload->>'synthetic_fixture','false')='true' then return jsonb_build_object('outcome','REJECTED','reason','SYNTHETIC_D_CLOSING_FORBIDDEN_IN_REAL_RUN'); end if;
   select * into v_d from public.kendel_component_registry where component_id='FULLUNDER_DEPURATION_D'; if not found or v_d.implementation_state not in ('KERNEL_CONNECTED','IMPLEMENTED') or v_d.runtime_state<>'ACTIVE' then return jsonb_build_object('outcome','REJECTED','reason','COUNTERPART_RUNTIME_NOT_PHYSICALLY_READY'); end if;
 end if;
 insert into public.fullunder_dep_a_counterpart_reports(run_id,producer_agent_id,report_type,report_sha256,report_payload,status) values(p_run,p_producer,'D_DIALOGUE_CLOSING_REPORT',p_sha,p_payload,case when r.test_mode then 'RECEIVED_VERIFIED_SYNTHETIC' else 'RECEIVED_VERIFIED' end) returning counterpart_report_id into v_id;
 update public.fullunder_dep_d_handoffs set acknowledged_by='@AnalistaDepuracionFullUnder_A',peer_receipt_id=v_id::text,acknowledged_at=now(),status=case when r.test_mode then 'ACKNOWLEDGED_TEST_ONLY' else 'DELIVERED_ACKNOWLEDGED' end where handoff_id=v_source;
 update public.fullunder_dep_a_runs set state_version=state_version+1,updated_at=now() where run_id=p_run;
 perform public.fuda_append_event(p_run,'D_DIALOGUE_CLOSING_RECEIVED','DIALOGUE',r.state_version+1,jsonb_build_object('counterpart_report_id',v_id,'source_handoff_id',v_source,'report_sha256',p_sha,'parent_report_sha256',v_parent.report_sha256,'upstream_packet_sha256',r.upstream_packet_sha256,'physical_lineage_verified',true,'test_mode',r.test_mode));
 return jsonb_build_object('outcome','ACCEPTED','counterpart_report_id',v_id,'source_handoff_id',v_source,'verified_sha256',p_sha,'parent_report_sha256',v_parent.report_sha256,'upstream_packet_sha256',r.upstream_packet_sha256,'state_version',r.state_version+1,'physical_lineage_verified',true,'test_mode',r.test_mode);
end $$;