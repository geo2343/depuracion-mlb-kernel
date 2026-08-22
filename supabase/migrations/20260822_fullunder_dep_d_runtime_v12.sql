-- @AnalistaDepuracionFullUnder_D V1.2 runtime reconciliation.
update public.fullunder_dep_d_requirement_ledger
set requirement_text='Validate the exact direct handoff contract D -> @AnalistaDepuracionFullUnder_A, preserve evidence-linked candidate identity, and preserve lineage so A can later prepare the stage handoff to @Investigarfullunder.'
where requirement_id='D-008';

alter table public.fullunder_dep_d_handoffs drop constraint if exists fullunder_dep_d_handoffs_run_id_key;
alter table public.fullunder_dep_d_handoffs drop constraint if exists fullunder_dep_d_handoffs_target_agent_id_check;
alter table public.fullunder_dep_d_handoffs add constraint fullunder_dep_d_handoffs_target_agent_id_check check (handoff_type is null or target_agent_id='@AnalistaDepuracionFullUnder_A');
create unique index if not exists fullunder_dep_d_handoffs_run_type_uq on public.fullunder_dep_d_handoffs(run_id,handoff_type) where handoff_type is not null;
create or replace function public.fullunder_dep_d_enforce_new_handoff_target() returns trigger language plpgsql set search_path='public' as $$ begin if new.target_agent_id<>'@AnalistaDepuracionFullUnder_A' then raise exception 'DIRECT_D_TO_NON_A_FORBIDDEN'; end if; return new; end $$;
drop trigger if exists fullunder_dep_d_new_handoff_target_guard on public.fullunder_dep_d_handoffs;
create trigger fullunder_dep_d_new_handoff_target_guard before insert or update of target_agent_id on public.fullunder_dep_d_handoffs for each row execute function public.fullunder_dep_d_enforce_new_handoff_target();

create or replace function public.fullunder_dep_d_start_run(p_upstream_agent_id text,p_upstream_run_id text,p_upstream_packet_id text,p_upstream_packet_sha256 text,p_upstream_as_of timestamp with time zone,p_slate_date date,p_test_mode boolean,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path='public','extensions','pg_temp' as $$
declare r uuid; m record; u record; v_source_test boolean;
begin
 if p_upstream_agent_id<>'@InvestigadorGlobalFullUnder' then raise exception 'WRONG_UPSTREAM_AGENT'; end if;
 if coalesce(length(btrim(p_upstream_run_id)),0)=0 or coalesce(length(btrim(p_upstream_packet_id)),0)=0 then raise exception 'UPSTREAM_IDENTITY_REQUIRED'; end if;
 if p_upstream_packet_sha256 !~ '^[0-9a-fA-F]{64}$' then raise exception 'INVALID_UPSTREAM_SHA256'; end if;
 if coalesce(length(btrim(p_idempotency_key)),0)<8 then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;
 select run_id into r from public.fullunder_dep_d_runs where idempotency_key=p_idempotency_key; if r is not null then return r; end if;
 select * into m from public.investigadorglobal_fullunder_handoff_manifests where run_id::text=p_upstream_run_id and packet_id=p_upstream_packet_id and packet_sha256=lower(p_upstream_packet_sha256) order by created_at desc limit 1;
 if not found then raise exception 'UPSTREAM_MANIFEST_NOT_PHYSICALLY_FOUND'; end if;
 if m.status not in ('PREPARED_WAITING_FOR_CONSUMER','DELIVERED','READBACK_VERIFIED') then raise exception 'UPSTREAM_HANDOFF_NOT_READY'; end if;
 if coalesce(m.packet_payload->>'producer','')<>'@InvestigadorGlobalFullUnder' then raise exception 'INVALID_UPSTREAM_PRODUCER'; end if;
 select * into u from public.investigadorglobal_fullunder_runs where run_id=m.run_id; if not found then raise exception 'UPSTREAM_RUN_NOT_FOUND'; end if;
 v_source_test:=coalesce(m.test_only,false) or coalesce((m.packet_payload#>>'{f9,test_only}')::boolean,false) or coalesce((u.metadata->>'test_only')::boolean,false) or coalesce((u.authorization_context->>'test_only')::boolean,false);
 if v_source_test and not coalesce(p_test_mode,false) then raise exception 'TEST_PACKET_REQUIRES_TEST_MODE'; end if;
 if not coalesce(p_test_mode,false) and v_source_test then raise exception 'SYNTHETIC_UPSTREAM_FORBIDDEN_REAL'; end if;
 if p_slate_date is distinct from u.slate_date then raise exception 'UPSTREAM_SLATE_DATE_MISMATCH'; end if;
 if p_upstream_as_of is distinct from u.as_of then raise exception 'UPSTREAM_AS_OF_MISMATCH'; end if;
 insert into public.fullunder_dep_d_runs(upstream_agent_id,upstream_run_id,upstream_packet_id,upstream_packet_sha256,upstream_as_of,slate_date,test_mode,idempotency_key,agent_id,agent_version)
 values('@InvestigadorGlobalFullUnder',p_upstream_run_id,p_upstream_packet_id,lower(p_upstream_packet_sha256),p_upstream_as_of,p_slate_date,coalesce(p_test_mode,false),p_idempotency_key,'@AnalistaDepuracionFullUnder_D','ANALISTADEPURACIONFULLUNDER-D-AGENT-1.2') returning run_id into r;
 insert into public.fullunder_dep_d_run_requirements(run_id,requirement_id) select r,requirement_id from public.fullunder_dep_d_requirement_ledger where active;
 insert into public.fullunder_dep_d_audit_trail(run_id,event_type,detail) values(r,'RUN_STARTED',jsonb_build_object('test_mode',p_test_mode,'upstream_manifest_id',m.manifest_id,'upstream_packet_sha256',m.packet_sha256,'physical_upstream_verified',true));
 return r;
end $$;

create or replace function public.fullunder_dep_d_record_counterpart(p_run_id uuid,p_peer_agent_id text,p_peer_report_id text,p_peer_report_sha256 text,p_convergence text,p_divergence text,p_material_effect text,p_expected_state_version bigint)
returns bigint language plpgsql security definer set search_path='public','pg_temp' as $$
declare v bigint; f boolean; r record; a record;
begin
 select * into r from public.fullunder_dep_d_runs where run_id=p_run_id for update; if not found then raise exception 'RUN_NOT_FOUND'; end if;
 v:=r.state_version; f:=r.pre_dialogue_frozen;
 if v<>p_expected_state_version then raise exception 'STALE_STATE_VERSION'; end if;
 if not f then raise exception 'D_MUST_FREEZE_BEFORE_READING_A'; end if;
 if r.initial_report_handoff_id is null then raise exception 'D_INITIAL_REPORT_HANDOFF_REQUIRED_BEFORE_A_INGEST'; end if;
 if p_peer_agent_id<>'@AnalistaDepuracionFullUnder_A' then raise exception 'WRONG_COUNTERPART_AGENT'; end if;
 if p_peer_report_sha256 !~ '^[0-9a-fA-F]{64}$' then raise exception 'INVALID_PEER_SHA256'; end if;
 begin
   select ar.*,rr.upstream_packet_sha256,rr.pre_dialogue_frozen as a_frozen into a from public.fullunder_dep_a_phase_artifacts ar join public.fullunder_dep_a_runs rr on rr.run_id=ar.run_id where ar.artifact_id=p_peer_report_id::uuid and ar.phase_id='REPORT' and ar.artifact_type='FINAL_DIALOGUE_REPORT_A' limit 1;
 exception when invalid_text_representation then raise exception 'INVALID_PEER_REPORT_ID'; end;
 if not found then raise exception 'A_REPORT_ARTIFACT_NOT_FOUND'; end if;
 if lower(a.artifact_sha256)<>lower(p_peer_report_sha256) then raise exception 'A_REPORT_SHA256_MISMATCH'; end if;
 if a.upstream_packet_sha256<>r.upstream_packet_sha256 then raise exception 'A_REPORT_DIFFERENT_UPSTREAM_PACKET'; end if;
 if not a.a_frozen then raise exception 'A_REPORT_NOT_PRE_DIALOGUE_FROZEN'; end if;
 insert into public.fullunder_dep_d_peer_exchange(run_id,peer_agent_id,peer_report_id,peer_report_sha256,convergence,divergence,material_effect) values(p_run_id,p_peer_agent_id,p_peer_report_id,lower(p_peer_report_sha256),p_convergence,p_divergence,p_material_effect);
 update public.fullunder_dep_d_runs set counterpart_report_received=true,a_dialogue_delta_received=true,state_version=state_version+1,updated_at=now() where run_id=p_run_id returning state_version into v;
 insert into public.fullunder_dep_d_audit_trail(run_id,event_type,detail) values(p_run_id,'A_REPORT_PHYSICALLY_VERIFIED',jsonb_build_object('a_report_id',p_peer_report_id,'a_report_sha256',lower(p_peer_report_sha256),'same_upstream_packet',true));
 return v;
end $$;

create or replace function public.fullunder_dep_d_create_handoff(p_run_id uuid,p_target_agent_id text,p_payload jsonb,p_expected_state_version bigint)
returns uuid language plpgsql security definer set search_path='public','extensions','pg_temp' as $$
declare r record; ids uuid[]; h uuid; ph text; v_type text; existing record; v_parent record; v_payload jsonb; v_in_hash text; v_existing_base_hash text;
begin
 select * into r from public.fullunder_dep_d_runs where run_id=p_run_id for update; if not found then raise exception 'RUN_NOT_FOUND'; end if;
 if r.state_version<>p_expected_state_version then raise exception 'STALE_STATE_VERSION'; end if;
 if p_target_agent_id<>'@AnalistaDepuracionFullUnder_A' then raise exception 'WRONG_DOWNSTREAM_AGENT'; end if;
 if coalesce(p_payload->>'producer_agent_id','')<>'@AnalistaDepuracionFullUnder_D' then raise exception 'HANDOFF_PRODUCER_IDENTITY_REQUIRED'; end if;
 if coalesce(p_payload->>'upstream_packet_sha256','')<>r.upstream_packet_sha256 then raise exception 'HANDOFF_UPSTREAM_HASH_MISMATCH'; end if;
 if r.status='PRE_DIALOGUE_FROZEN' and not r.counterpart_report_received then
   v_type:='FINAL_DIALOGUE_REPORT_D';
   if coalesce(p_payload->>'report_type','')<>v_type then raise exception 'INITIAL_D_REPORT_TYPE_REQUIRED'; end if;
   select * into existing from public.fullunder_dep_d_handoffs where run_id=p_run_id and handoff_type=v_type limit 1;
   if found then v_in_hash:=encode(extensions.digest(coalesce(p_payload,'{}'::jsonb)::text,'sha256'),'hex'); v_existing_base_hash:=encode(extensions.digest((existing.payload-'source_handoff_id')::text,'sha256'),'hex'); if v_in_hash=v_existing_base_hash then return existing.handoff_id; end if; raise exception 'INITIAL_D_REPORT_ALREADY_EXISTS_DIFFERENT_PAYLOAD'; end if;
   select array_agg(candidate_id order by candidate_id) into ids from public.fullunder_dep_d_candidate_state where run_id=p_run_id;
   if coalesce(array_length(ids,1),0)=0 then raise exception 'NO_CANDIDATE_ASSESSMENTS_FOR_REPORT'; end if;
   h:=gen_random_uuid(); v_payload:=coalesce(p_payload,'{}'::jsonb)||jsonb_build_object('source_handoff_id',h::text,'producer_version',r.agent_version);
   if r.test_mode then v_payload:=v_payload||jsonb_build_object('test_only',true,'synthetic_fixture',true,'fixture_kind','SYNTHETIC_D_DIALOGUE_REPORT'); else if coalesce((v_payload->>'test_only')::boolean,false) or coalesce((v_payload->>'synthetic_fixture')::boolean,false) then raise exception 'SYNTHETIC_D_REPORT_FORBIDDEN_REAL'; end if; end if;
   ph:=encode(extensions.digest(v_payload::text,'sha256'),'hex');
   insert into public.fullunder_dep_d_handoffs(handoff_id,run_id,target_agent_id,candidate_ids,payload,payload_sha256,status,handoff_type) values(h,p_run_id,p_target_agent_id,ids,v_payload,ph,case when r.test_mode then 'PREPARED_TEST_ONLY_DO_NOT_CONSUME' else 'PREPARED_WAITING_FOR_CONSUMER' end,v_type);
   update public.fullunder_dep_d_runs set initial_report_handoff_id=h,state_version=state_version+1,updated_at=now() where run_id=p_run_id;
   insert into public.fullunder_dep_d_audit_trail(run_id,event_type,detail) values(p_run_id,'INITIAL_D_REPORT_HANDOFF_CREATED',jsonb_build_object('handoff_id',h,'sha256',ph,'target',p_target_agent_id,'self_identifying_payload',true)); return h;
 elsif r.status='COMPLETE' and r.counterpart_report_received then
   v_type:='D_DIALOGUE_CLOSING_REPORT';
   if coalesce(p_payload->>'report_type','')<>v_type then raise exception 'D_CLOSING_REPORT_TYPE_REQUIRED'; end if;
   if coalesce(p_payload->>'closing_outcome','') not in ('NO_FURTHER_MATERIAL_OBJECTION','UNRESOLVED_MATERIAL') then raise exception 'INVALID_D_CLOSING_OUTCOME'; end if;
   if coalesce((p_payload->>'d_final_post_dialogue_authority')::boolean,false)=true then raise exception 'D_CANNOT_CLAIM_FINAL_POST_DIALOGUE_AUTHORITY'; end if;
   select * into v_parent from public.fullunder_dep_d_handoffs where handoff_id=r.initial_report_handoff_id; if not found then raise exception 'INITIAL_D_REPORT_HANDOFF_NOT_FOUND'; end if;
   if coalesce(p_payload->>'parent_report_sha256','')<>v_parent.payload_sha256 then raise exception 'D_CLOSING_WRONG_PARENT_REPORT'; end if;
   select * into existing from public.fullunder_dep_d_handoffs where run_id=p_run_id and handoff_type=v_type limit 1;
   if found then v_in_hash:=encode(extensions.digest(coalesce(p_payload,'{}'::jsonb)::text,'sha256'),'hex'); v_existing_base_hash:=encode(extensions.digest((existing.payload-'source_handoff_id'-'producer_version'-'fixture_kind'-'test_only'-'synthetic_fixture')::text,'sha256'),'hex'); if v_in_hash=v_existing_base_hash then return existing.handoff_id; end if; raise exception 'D_CLOSING_ALREADY_EXISTS_DIFFERENT_PAYLOAD'; end if;
   select array_agg(candidate_id order by candidate_id) into ids from public.fullunder_dep_d_candidate_state where run_id=p_run_id;
   h:=gen_random_uuid(); v_payload:=coalesce(p_payload,'{}'::jsonb)||jsonb_build_object('source_handoff_id',h::text,'producer_version',r.agent_version);
   if r.test_mode then v_payload:=v_payload||jsonb_build_object('test_only',true,'synthetic_fixture',true,'fixture_kind','SYNTHETIC_D_DIALOGUE_CLOSING'); else if coalesce((v_payload->>'test_only')::boolean,false) or coalesce((v_payload->>'synthetic_fixture')::boolean,false) then raise exception 'SYNTHETIC_D_CLOSING_FORBIDDEN_REAL'; end if; end if;
   ph:=encode(extensions.digest(v_payload::text,'sha256'),'hex');
   insert into public.fullunder_dep_d_handoffs(handoff_id,run_id,target_agent_id,candidate_ids,payload,payload_sha256,status,handoff_type) values(h,p_run_id,p_target_agent_id,coalesce(ids,array[]::uuid[]),v_payload,ph,case when r.test_mode then 'PREPARED_TEST_ONLY_DO_NOT_CONSUME' else 'PREPARED_WAITING_FOR_CONSUMER' end,v_type);
   update public.fullunder_dep_d_runs set closing_handoff_id=h,final_handoff_id=h,state_version=state_version+1,updated_at=now() where run_id=p_run_id;
   insert into public.fullunder_dep_d_audit_trail(run_id,event_type,detail) values(p_run_id,'D_CLOSING_HANDOFF_CREATED',jsonb_build_object('handoff_id',h,'sha256',ph,'parent_sha256',v_parent.payload_sha256,'target',p_target_agent_id,'self_identifying_payload',true)); return h;
 else raise exception 'HANDOFF_NOT_ALLOWED_IN_CURRENT_STATE'; end if;
exception when invalid_text_representation then raise exception 'INVALID_D_AUTHORITY_FLAG';
end $$;