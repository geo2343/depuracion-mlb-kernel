-- DEP-MLB-KERNEL-0.5-EXHAUSTIVE-SELECTIVE
-- Production migration: dep_mlb_kernel_05_exhaustive_selective_refactor

alter table public.dep_mlb_game_packets drop constraint if exists dep_mlb_game_packets_depth_mode_check;
alter table public.dep_mlb_game_packets add constraint dep_mlb_game_packets_depth_mode_check
  check (depth_mode is null or depth_mode in ('STOP','STANDARD','DISCRIMINANT','EXHAUSTIVE'));

create table if not exists public.dep_mlb_run_audit_verdicts (
  verdict_id uuid primary key default gen_random_uuid(),
  run_id text not null references public.dep_mlb_runs(run_id) on delete cascade,
  audit_version text not null,
  verdict text not null check (verdict in ('PASS','FAIL','CONDITIONED')),
  reasons jsonb not null default '[]'::jsonb,
  sports_certification_valid boolean not null default false,
  created_at timestamptz not null default now(),
  unique(run_id,audit_version)
);
alter table public.dep_mlb_run_audit_verdicts enable row level security;

create or replace function public.dep_mlb_is_v05_run(p_run text)
returns boolean language sql stable set search_path to 'public','pg_temp' as $$
select exists(select 1 from public.dep_mlb_runs r where r.run_id=p_run and r.agent_version='DEP-MLB-AGENT-1.3' and r.kernel_version='DEP-MLB-KERNEL-0.5-EXHAUSTIVE-SELECTIVE');
$$;

create or replace function public.dep_mlb_v05_tool_event_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare rs text; f9 text;
begin
  if not public.dep_mlb_is_v05_run(new.run_id) then return new; end if;
  select run_status into rs from public.dep_mlb_runs where run_id=new.run_id;
  if rs='COMPLETED' then raise exception 'DEP_MLB_V05_COMPLETED_RUN_REJECTS_NEW_TOOL_EVENTS'; end if;
  select state into f9 from public.dep_mlb_phase_state where run_id=new.run_id and phase_code='F9';
  if new.connector_name='Web' and f9='PASS' then raise exception 'DEP_MLB_V05_WEB_RESEARCH_AFTER_F9_REQUIRES_NEW_RUN'; end if;
  if new.game_id is not null and not exists(select 1 from public.dep_mlb_games where run_id=new.run_id and game_id=new.game_id) then raise exception 'DEP_MLB_V05_TOOL_EVENT_GAME_RUN_MISMATCH'; end if;
  if tg_op='INSERT' then new.requested_at:=clock_timestamp(); new.completed_at:=clock_timestamp(); end if;
  if new.success then
    if new.response_snapshot is null or new.response_snapshot='{}'::jsonb then raise exception 'DEP_MLB_V05_SUCCESSFUL_TOOL_EVENT_REQUIRES_RESPONSE_SNAPSHOT'; end if;
    if new.connector_name='Web' and (nullif(trim(coalesce(new.source_url,'')),'') is null or nullif(trim(coalesce(new.source_origin,'')),'') is null or new.source_as_of is null or nullif(trim(coalesce(new.metadata->>'web_ref','')),'') is null) then raise exception 'DEP_MLB_V05_WEB_EVENT_REQUIRES_URL_ORIGIN_ASOF_PROVIDER_REF'; end if;
    new.response_hash:=encode(extensions.digest(new.response_snapshot::text,'sha256'),'hex');
  end if;
  return new;
end $$;
drop trigger if exists dep_mlb_00_v05_tool_event_guard on public.dep_mlb_tool_events;
create trigger dep_mlb_00_v05_tool_event_guard before insert or update on public.dep_mlb_tool_events for each row execute function public.dep_mlb_v05_tool_event_guard();

create or replace function public.dep_mlb_v05_evidence_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare te public.dep_mlb_tool_events%rowtype; fp timestamptz;
begin
  if not public.dep_mlb_is_v05_run(new.run_id) then return new; end if;
  select * into te from public.dep_mlb_tool_events where tool_event_id=new.tool_event_id;
  if not found or te.run_id<>new.run_id or te.game_id is distinct from new.game_id or not te.success then raise exception 'DEP_MLB_V05_EVIDENCE_TOOL_EVENT_INVALID'; end if;
  if new.snapshot is null or new.snapshot='{}'::jsonb then raise exception 'DEP_MLB_V05_EVIDENCE_REQUIRES_SNAPSHOT'; end if;
  if new.evidence_scope='SPORTS_RESEARCH' then
    if te.connector_name<>'Web' then raise exception 'DEP_MLB_V05_SPORTS_EVIDENCE_REQUIRES_WEB'; end if;
    if nullif(trim(coalesce(new.source_family,'')),'') is null then raise exception 'DEP_MLB_V05_SPORTS_EVIDENCE_REQUIRES_SOURCE_FAMILY'; end if;
    if te.source_url is null or te.source_origin is null or te.source_as_of is null then raise exception 'DEP_MLB_V05_SPORTS_EVIDENCE_REQUIRES_SOURCE_IDENTITY'; end if;
  end if;
  new.tool_response_hash:=te.response_hash;
  new.captured_at:=clock_timestamp();
  new.snapshot_hash:=encode(extensions.digest(new.snapshot::text,'sha256'),'hex');
  new.source_url:=te.source_url; new.source_origin:=te.source_origin; new.source_as_of:=te.source_as_of;
  select first_pitch into fp from public.dep_mlb_games where run_id=new.run_id and game_id=new.game_id;
  if new.evidence_scope='SPORTS_RESEARCH' and fp is not null and (new.captured_at>=fp or new.source_as_of>=fp) then raise exception 'DEP_MLB_V05_POST_FIRST_PITCH_SPORTS_EVIDENCE_FORBIDDEN'; end if;
  return new;
end $$;
drop trigger if exists dep_mlb_evidence_00_v05_source_guard on public.dep_mlb_evidence;
create trigger dep_mlb_evidence_00_v05_source_guard before insert or update on public.dep_mlb_evidence for each row execute function public.dep_mlb_v05_evidence_guard();

create or replace function public.dep_mlb_v05_claim_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare fp timestamptz; ps text;
begin
  if not public.dep_mlb_is_v05_run(new.run_id) then return new; end if;
  if new.phase_code is null or public.dep_mlb_phase_order_of(new.phase_code) not between 2 and 9 then raise exception 'DEP_MLB_V05_CLAIM_REQUIRES_PHASE_F2_F9'; end if;
  if length(trim(coalesce(new.claim_text,'')))<20 then raise exception 'DEP_MLB_V05_CLAIM_TEXT_TOO_THIN'; end if;
  if new.claim_type not in ('FAVORABLE_MECHANISM','ADVERSE_ROUTE','FULL_GAME_SYNTHESIS') then raise exception 'DEP_MLB_V05_CLAIM_TYPE_INVALID'; end if;
  select first_pitch into fp from public.dep_mlb_games where run_id=new.run_id and game_id=new.game_id;
  if fp is not null and clock_timestamp()>=fp then raise exception 'DEP_MLB_V05_CLAIM_AFTER_FIRST_PITCH_FORBIDDEN'; end if;
  select state into ps from public.dep_mlb_phase_state where run_id=new.run_id and phase_code=new.phase_code;
  if ps='PASS' and new.superseded_at is null then raise exception 'DEP_MLB_V05_CLAIM_AFTER_PHASE_PASS_FORBIDDEN'; end if;
  return new;
end $$;
drop trigger if exists dep_mlb_claim_00_v05_guard on public.dep_mlb_claims;
create trigger dep_mlb_claim_00_v05_guard before insert or update on public.dep_mlb_claims for each row execute function public.dep_mlb_v05_claim_guard();

create or replace function public.dep_mlb_v05_phase_artifact_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare eid uuid; teid uuid; erun text; egame text; fp timestamptz; earliest_fp timestamptz; k text; required_keys text[]; fam_count integer; ev_count integer; f8 jsonb;
begin
  if not public.dep_mlb_is_v05_run(new.run_id) then return new; end if;
  if exists(select 1 from public.dep_mlb_phase_state ps where ps.run_id=new.run_id and ps.phase_code=new.phase_code and ps.state='PASS') then raise exception 'DEP_MLB_V05_CANNOT_WRITE_ARTIFACT_AFTER_PHASE_PASS'; end if;
  if new.phase_code='F1' then
    if new.game_id is not null or new.artifact_type<>'UNIVERSE_SNAPSHOT' then raise exception 'DEP_MLB_V05_F1_REQUIRES_SLATE_UNIVERSE_ARTIFACT'; end if;
    required_keys:=array['daily_mlb_universe','data_dependency_map','snapshot_as_of','identity_reconciliation','reasoning'];
  else
    if new.game_id is null and new.phase_code<>'F9' then raise exception 'DEP_MLB_V05_GAME_PHASE_ARTIFACT_REQUIRES_GAME'; end if;
    if new.game_id is not null then
      select first_pitch into fp from public.dep_mlb_games where run_id=new.run_id and game_id=new.game_id;
      if fp is null or clock_timestamp()>=fp then raise exception 'DEP_MLB_V05_PHASE_ARTIFACT_AFTER_FIRST_PITCH_FORBIDDEN'; end if;
    end if;
    if new.phase_code='F2' then required_keys:=array['starter_representation','current_version','material_risks','reasoning']; if new.artifact_type<>'STARTER_SCREEN' then raise exception 'DEP_MLB_V05_F2_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F3' then required_keys:=array['offense_representation','production_routes','material_risks','reasoning']; if new.artifact_type<>'OFFENSE_SCREEN' then raise exception 'DEP_MLB_V05_F3_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F4' then required_keys:=array['bullpen_context','full_game_effect','material_risks','reasoning']; if new.artifact_type<>'BULLPEN_CONTEXT_SCREEN' then raise exception 'DEP_MLB_V05_F4_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F5' then required_keys:=array['favorable_mechanisms','adverse_routes','governing_architecture','depth_decision','next_state','reasoning']; if new.artifact_type<>'STRUCTURAL_CROSS' then raise exception 'DEP_MLB_V05_F5_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F6' then required_keys:=array['research_required','deep_question','resolution','classification_effect','verification_result','reasoning']; if new.artifact_type<>'DISCRIMINANT_RESOLUTION' then raise exception 'DEP_MLB_V05_F6_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F7' then required_keys:=array['full_game_viability','starter_horizon','transition','bullpen_reachability','reasoning']; if new.artifact_type<>'FULL_GAME_VIABILITY' then raise exception 'DEP_MLB_V05_F7_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F8' then required_keys:=array['containment_case','escalation_case','materialization_path','best_explanation','full_game_chain_status','independent_containment_mechanisms','governing_failure_route','reasoning']; if new.artifact_type<>'MATERIALIZATION_COUNTERCASE' then raise exception 'DEP_MLB_V05_F8_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F9' and new.game_id is not null then required_keys:=array['red_team','false_positive_check','false_negative_check','comparative_position','candidate_gate','red_team_verdict','comparative_verdict','full_game_chain_status','independent_containment_mechanisms','governing_failure_route','final_classification','reasoning']; if new.artifact_type<>'RED_TEAM_RESULT' then raise exception 'DEP_MLB_V05_F9_GAME_ARTIFACT_TYPE_INVALID'; end if;
    elsif new.phase_code='F9' and new.game_id is null then required_keys:=array['ranking_logic','best_excluded','last_candidate_vs_best_excluded','empty_slots_justification','candidate_count','reasoning']; if new.artifact_type<>'HORIZONTAL_AUDIT' then raise exception 'DEP_MLB_V05_F9_SLATE_ARTIFACT_TYPE_INVALID'; end if;
    else raise exception 'DEP_MLB_V05_PHASE_ARTIFACT_PHASE_NOT_SUPPORTED'; end if;
  end if;
  foreach k in array required_keys loop
    if not(new.content?k) then raise exception 'DEP_MLB_V05_PHASE_ARTIFACT_MISSING_FIELD:%',k; end if;
    if jsonb_typeof(new.content->k)='string' and length(trim(new.content->>k))<3 then raise exception 'DEP_MLB_V05_PHASE_ARTIFACT_FIELD_EMPTY:%',k; end if;
  end loop;
  if length(trim(coalesce(new.content->>'reasoning','')))<60 then raise exception 'DEP_MLB_V05_PHASE_ARTIFACT_REASONING_TOO_THIN'; end if;
  if new.phase_code='F1' then
    if cardinality(new.tool_event_ids)<1 then raise exception 'DEP_MLB_V05_F1_REQUIRES_UNIVERSE_TOOL_EVENT'; end if;
    select min(first_pitch) into earliest_fp from public.dep_mlb_games where run_id=new.run_id and eligible_pregame;
    if earliest_fp is null or clock_timestamp()>=earliest_fp then raise exception 'DEP_MLB_V05_F1_AFTER_EARLIEST_FIRST_PITCH_FORBIDDEN'; end if;
  else
    if (new.phase_code in ('F2','F3','F4','F5','F6','F7','F8') or (new.phase_code='F9' and new.game_id is not null)) and cardinality(new.evidence_ids)<1 then raise exception 'DEP_MLB_V05_GAME_PHASE_REQUIRES_EVIDENCE'; end if;
    foreach eid in array new.evidence_ids loop
      select run_id,game_id into erun,egame from public.dep_mlb_evidence where evidence_id=eid;
      if not found or erun<>new.run_id or (new.game_id is not null and egame<>new.game_id) then raise exception 'DEP_MLB_V05_PHASE_EVIDENCE_LINEAGE_INVALID'; end if;
    end loop;
    foreach teid in array new.tool_event_ids loop
      if not exists(select 1 from public.dep_mlb_tool_events t where t.tool_event_id=teid and t.run_id=new.run_id and t.success) then raise exception 'DEP_MLB_V05_PHASE_TOOL_EVENT_INVALID'; end if;
    end loop;
    if new.game_id is not null then
      select count(distinct e.evidence_id),count(distinct e.source_family) into ev_count,fam_count from public.dep_mlb_evidence e where e.evidence_id=any(new.evidence_ids) and e.run_id=new.run_id and e.game_id=new.game_id;
      if new.phase_code='F2' and not exists(select 1 from public.dep_mlb_evidence e where e.evidence_id=any(new.evidence_ids) and e.source_family='STARTER_PROFILE') then raise exception 'DEP_MLB_V05_F2_REQUIRES_STARTER_PROFILE_EVIDENCE'; end if;
      if new.phase_code='F3' and not exists(select 1 from public.dep_mlb_evidence e where e.evidence_id=any(new.evidence_ids) and e.source_family='OFFENSE_PROFILE') then raise exception 'DEP_MLB_V05_F3_REQUIRES_OFFENSE_PROFILE_EVIDENCE'; end if;
      if new.phase_code='F4' and not exists(select 1 from public.dep_mlb_evidence e where e.evidence_id=any(new.evidence_ids) and e.source_family='BULLPEN_CONTEXT') then raise exception 'DEP_MLB_V05_F4_REQUIRES_DEDICATED_BULLPEN_EVIDENCE'; end if;
      if new.phase_code='F5' and (ev_count<3 or fam_count<3) then raise exception 'DEP_MLB_V05_F5_REQUIRES_THREE_EVIDENCE_FAMILIES'; end if;
      if new.phase_code='F6' then
        if coalesce((new.content->>'research_required')::boolean,false) is not true then raise exception 'DEP_MLB_V05_F6_REQUIRES_DEEP_RESEARCH'; end if;
        if not exists(select 1 from public.dep_mlb_evidence e where e.evidence_id=any(new.evidence_ids) and e.source_family='DEEP_VERIFICATION') then raise exception 'DEP_MLB_V05_F6_REQUIRES_DEEP_VERIFICATION_EVIDENCE'; end if;
      end if;
      if new.phase_code in ('F7','F8','F9') and (ev_count<4 or fam_count<4) then raise exception 'DEP_MLB_V05_F7_F9_REQUIRE_FOUR_EVIDENCE_FAMILIES'; end if;
    end if;
  end if;
  if new.phase_code='F5' and (new.content->>'depth_decision'<>'EXHAUSTIVE' or new.content->>'next_state'<>'CONTINUE') then raise exception 'DEP_MLB_V05_F5_MUST_CONTINUE_EXHAUSTIVE'; end if;
  if new.phase_code='F8' then
    if new.content->>'full_game_chain_status' not in ('COMPLETE','FRAGILE') then raise exception 'DEP_MLB_V05_F8_FULL_GAME_CHAIN_STATUS_INVALID'; end if;
    if jsonb_typeof(new.content->'independent_containment_mechanisms')<>'array' then raise exception 'DEP_MLB_V05_F8_MECHANISMS_ARRAY_REQUIRED'; end if;
  end if;
  if new.phase_code='F9' and new.game_id is not null then
    if new.content->>'final_classification' not in ('PRIMARY_CANDIDATE','NOT_ADVANCED') then raise exception 'DEP_MLB_V05_F9_FINAL_CLASSIFICATION_INVALID'; end if;
    if new.content->>'candidate_gate' not in ('PASS','FAIL') or new.content->>'red_team_verdict' not in ('SURVIVES','FAILS') or new.content->>'comparative_verdict' not in ('TOP_TWO','OUTSIDE_TOP_TWO') or new.content->>'full_game_chain_status' not in ('COMPLETE','FRAGILE') then raise exception 'DEP_MLB_V05_F9_ADMISSION_ENUM_INVALID'; end if;
    if jsonb_typeof(new.content->'independent_containment_mechanisms')<>'array' then raise exception 'DEP_MLB_V05_F9_MECHANISMS_ARRAY_REQUIRED'; end if;
    select content into f8 from public.dep_mlb_phase_artifacts where run_id=new.run_id and game_id=new.game_id and phase_code='F8' and artifact_type='MATERIALIZATION_COUNTERCASE' and superseded_at is null;
    if f8 is null then raise exception 'DEP_MLB_V05_F9_REQUIRES_F8'; end if;
    if new.content->>'final_classification'='PRIMARY_CANDIDATE' then
      if new.content->>'candidate_gate'<>'PASS' or new.content->>'red_team_verdict'<>'SURVIVES' or new.content->>'comparative_verdict'<>'TOP_TWO' or new.content->>'full_game_chain_status'<>'COMPLETE' then raise exception 'DEP_MLB_V05_CANDIDATE_ADMISSION_BURDEN_NOT_MET'; end if;
      if jsonb_array_length(new.content->'independent_containment_mechanisms')<2 or f8->>'full_game_chain_status'<>'COMPLETE' or jsonb_array_length(f8->'independent_containment_mechanisms')<2 then raise exception 'DEP_MLB_V05_CANDIDATE_REQUIRES_TWO_INDEPENDENT_MECHANISMS'; end if;
    else
      if new.content->>'candidate_gate'<>'FAIL' or new.content->>'comparative_verdict'<>'OUTSIDE_TOP_TWO' then raise exception 'DEP_MLB_V05_NOT_ADVANCED_GATE_MISMATCH'; end if;
    end if;
  end if;
  new.content_hash:=encode(extensions.digest(new.content::text,'sha256'),'hex');
  return new;
end $$;
drop trigger if exists dep_mlb_00_v05_phase_artifact_guard on public.dep_mlb_phase_artifacts;
create trigger dep_mlb_00_v05_phase_artifact_guard before insert or update on public.dep_mlb_phase_artifacts for each row execute function public.dep_mlb_v05_phase_artifact_guard();

create or replace function public.dep_mlb_v05_phase_state_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare total_games integer; artifact_games integer; prev_state text; earliest_fp timestamptz; prim integer; pot integer; handoff_pass integer; good_packets integer;
begin
  if not public.dep_mlb_is_v05_run(new.run_id) then return new; end if;
  if old.state='PASS' and to_jsonb(new)<>to_jsonb(old) then raise exception 'DEP_MLB_V05_PASSED_PHASE_IMMUTABLE'; end if;
  if new.state in ('IN_PROGRESS','PASS') and new.phase_order>0 then select state into prev_state from public.dep_mlb_phase_state where run_id=new.run_id and phase_order=new.phase_order-1; if prev_state is distinct from 'PASS' then raise exception 'DEP_MLB_V05_PHASE_ORDER_VIOLATION'; end if; end if;
  if new.state='IN_PROGRESS' and new.started_at is null then new.started_at:=clock_timestamp(); end if;
  if new.state<>'PASS' then return new; end if;
  select count(*) into total_games from public.dep_mlb_games where run_id=new.run_id and eligible_pregame;
  select min(first_pitch) into earliest_fp from public.dep_mlb_games where run_id=new.run_id and eligible_pregame;
  if earliest_fp is null or clock_timestamp()>=earliest_fp then raise exception 'DEP_MLB_V05_TEMPORAL_WINDOW_MISSED'; end if;
  if new.phase_code='F1' then
    if total_games<1 or not exists(select 1 from public.dep_mlb_runs r where r.run_id=new.run_id and r.snapshot_as_of is not null and r.report_drive_file_id is not null) then raise exception 'DEP_MLB_V05_F1_REQUIRES_SNAPSHOT_AND_REPORT'; end if;
    if exists(select 1 from public.dep_mlb_games g where g.run_id=new.run_id and g.eligible_pregame and (g.first_pitch is null or g.first_pitch<=clock_timestamp())) then raise exception 'DEP_MLB_V05_F1_REQUIRES_ALL_GAMES_PREGAME'; end if;
    if not exists(select 1 from public.dep_mlb_phase_artifacts where run_id=new.run_id and phase_code='F1' and game_id is null and artifact_type='UNIVERSE_SNAPSHOT' and superseded_at is null) then raise exception 'DEP_MLB_V05_F1_REQUIRES_UNIVERSE_ARTIFACT'; end if;
    update public.dep_mlb_games set snapshot_hash=encode(extensions.digest(jsonb_build_object('game_id',game_id,'away_team',away_team,'home_team',home_team,'first_pitch',first_pitch,'venue',venue,'eligible_pregame',eligible_pregame)::text,'sha256'),'hex') where run_id=new.run_id and eligible_pregame;
    update public.dep_mlb_runs set universe_hash=public.dep_mlb_compute_universe_hash(new.run_id),universe_frozen_at=clock_timestamp(),updated_at=clock_timestamp() where run_id=new.run_id;
  elsif new.phase_code in ('F2','F3','F4','F5','F6','F7','F8') then
    select count(distinct game_id) into artifact_games from public.dep_mlb_phase_artifacts where run_id=new.run_id and phase_code=new.phase_code and game_id is not null and superseded_at is null;
    if artifact_games<>total_games then raise exception 'DEP_MLB_V05_PHASE_REQUIRES_ALL_GAMES:%/%',artifact_games,total_games; end if;
  elsif new.phase_code='F9' then
    select count(distinct game_id) into artifact_games from public.dep_mlb_phase_artifacts where run_id=new.run_id and phase_code='F9' and artifact_type='RED_TEAM_RESULT' and game_id is not null and superseded_at is null;
    if artifact_games<>total_games then raise exception 'DEP_MLB_V05_F9_REQUIRES_ALL_GAME_RED_TEAM_ARTIFACTS'; end if;
    if not exists(select 1 from public.dep_mlb_phase_artifacts where run_id=new.run_id and phase_code='F9' and game_id is null and artifact_type='HORIZONTAL_AUDIT' and superseded_at is null) then raise exception 'DEP_MLB_V05_F9_REQUIRES_HORIZONTAL_AUDIT'; end if;
    update public.dep_mlb_games g set final_classification=a.content->>'final_classification',minimum_comparative_closure=true,updated_at=clock_timestamp() from public.dep_mlb_phase_artifacts a where a.run_id=new.run_id and a.game_id=g.game_id and a.phase_code='F9' and a.artifact_type='RED_TEAM_RESULT' and a.superseded_at is null and g.run_id=new.run_id;
    select count(*) filter(where final_classification='PRIMARY_CANDIDATE'),count(*) filter(where final_classification='POTENTIAL_CANDIDATE') into prim,pot from public.dep_mlb_games where run_id=new.run_id and eligible_pregame;
    if prim>2 or pot<>0 then raise exception 'DEP_MLB_V05_MAX_TWO_CANDIDATES_TOTAL'; end if;
  elsif new.phase_code='F10' then
    select count(*) into handoff_pass from public.dep_mlb_handoffs where run_id=new.run_id and validation_status='PASS' and core_mission_complete and drive_report_complete and chat_report_complete and delivery_status='COMPLETE';
    select count(distinct game_id) into good_packets from public.dep_mlb_game_packets where run_id=new.run_id and frozen_at is not null and process_audit_status='PASS';
    if handoff_pass<>1 or good_packets<>total_games then raise exception 'DEP_MLB_V05_F10_REQUIRES_COMPLETE_DELIVERY_AND_ALL_AUDITED_PACKETS'; end if;
    if not exists(select 1 from public.dep_mlb_chat_reports where run_id=new.run_id and qa_status='PASS' and frozen_at is not null and content->'delivery_qa'->>'delivery_status'='COMPLETE') then raise exception 'DEP_MLB_V05_F10_REQUIRES_FINAL_CHAT_R1'; end if;
  end if;
  new.completion_hash:=public.dep_mlb_compute_phase_hash(new.run_id,new.phase_code); new.completed_at:=clock_timestamp(); new.gate_result:='PASS';
  return new;
end $$;
drop trigger if exists dep_mlb_00_v05_phase_state_guard on public.dep_mlb_phase_state;
create trigger dep_mlb_00_v05_phase_state_guard before update on public.dep_mlb_phase_state for each row execute function public.dep_mlb_v05_phase_state_guard();

create or replace function public.dep_mlb_v05_packet_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare f9 text; fp timestamptz; earliest_fp timestamptz; final_class text; canon jsonb;
begin
  if not public.dep_mlb_is_v05_run(new.run_id) then return new; end if;
  if tg_op='UPDATE' and old.frozen_at is not null then if to_jsonb(new)-'process_audit_status'<>to_jsonb(old)-'process_audit_status' then raise exception 'DEP_MLB_V05_FROZEN_PACKET_IMMUTABLE'; end if; return new; end if;
  if new.frozen_at is null then return new; end if;
  select state into f9 from public.dep_mlb_phase_state where run_id=new.run_id and phase_code='F9'; if f9<>'PASS' then raise exception 'DEP_MLB_V05_PACKET_FREEZE_REQUIRES_F9_PASS'; end if;
  select first_pitch,final_classification into fp,final_class from public.dep_mlb_games where run_id=new.run_id and game_id=new.game_id;
  select min(first_pitch) into earliest_fp from public.dep_mlb_games where run_id=new.run_id and eligible_pregame;
  if fp is null or earliest_fp is null or clock_timestamp()>=fp or clock_timestamp()>=earliest_fp then raise exception 'DEP_MLB_V05_PACKET_FREEZE_AFTER_TEMPORAL_WINDOW'; end if;
  if new.classification<>final_class or new.classification not in ('PRIMARY_CANDIDATE','NOT_ADVANCED') then raise exception 'DEP_MLB_V05_PACKET_CLASSIFICATION_INVALID'; end if;
  if new.depth_mode<>'EXHAUSTIVE' then raise exception 'DEP_MLB_V05_PACKET_DEPTH_MUST_BE_EXHAUSTIVE'; end if;
  if not exists(select 1 from public.dep_mlb_claims c where c.run_id=new.run_id and c.game_id=new.game_id and c.superseded_at is null and c.claim_type='FAVORABLE_MECHANISM') or not exists(select 1 from public.dep_mlb_claims c where c.run_id=new.run_id and c.game_id=new.game_id and c.superseded_at is null and c.claim_type='ADVERSE_ROUTE') or not exists(select 1 from public.dep_mlb_claims c where c.run_id=new.run_id and c.game_id=new.game_id and c.superseded_at is null and c.claim_type='FULL_GAME_SYNTHESIS') then raise exception 'DEP_MLB_V05_PACKET_REQUIRES_THREE_CAUSAL_CLAIM_TYPES'; end if;
  if new.drive_file_id is null or new.drive_hash is null or not exists(select 1 from public.dep_mlb_drive_artifacts d where d.run_id=new.run_id and d.game_id=new.game_id and d.drive_file_id=new.drive_file_id and d.content_hash=new.drive_hash and d.verified_readback=true and d.readback_tool_event_id is not null) then raise exception 'DEP_MLB_V05_FREEZE_REQUIRES_EVENT_ATTESTED_DRIVE_READBACK'; end if;
  canon:=jsonb_build_object('run_id',new.run_id,'game_id',new.game_id,'packet_version',new.packet_version,'phase_reached',new.phase_reached,'depth_mode',new.depth_mode,'governing_architecture',new.governing_architecture,'strongest_countercase',new.strongest_countercase,'material_uncertainties',new.material_uncertainties,'advancement_reason',new.advancement_reason,'change_condition',new.change_condition,'research_stop_reason',new.research_stop_reason,'reasoning',new.reasoning,'classification',new.classification,'previous_packet_hash',new.previous_packet_hash,'drive_file_id',new.drive_file_id,'drive_hash',new.drive_hash);
  new.packet_hash:=encode(extensions.digest(canon::text,'sha256'),'hex'); new.frozen_at:=clock_timestamp();
  return new;
end $$;
drop trigger if exists dep_mlb_00_v05_packet_guard on public.dep_mlb_game_packets;
create trigger dep_mlb_00_v05_packet_guard before insert or update on public.dep_mlb_game_packets for each row execute function public.dep_mlb_v05_packet_guard();

create or replace function public.dep_mlb_v05_process_audit_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare p public.dep_mlb_game_packets%rowtype; tool_count integer; evidence_count integer; source_families integer; source_origins integer; claim_count integer; art_count integer; pass_count integer; drive_ok boolean; earliest_fp timestamptz; claim_types integer;
begin
  if not public.dep_mlb_is_v05_run(new.run_id) then return new; end if;
  select * into p from public.dep_mlb_game_packets where packet_id=new.packet_id;
  if not found or p.run_id<>new.run_id or p.game_id<>new.game_id then raise exception 'DEP_MLB_V05_AUDIT_PACKET_LINEAGE_INVALID'; end if;
  select count(*) into tool_count from public.dep_mlb_tool_events where run_id=new.run_id and game_id=new.game_id and success;
  select count(*),count(distinct source_family),count(distinct source_origin) into evidence_count,source_families,source_origins from public.dep_mlb_evidence where run_id=new.run_id and game_id=new.game_id and evidence_scope='SPORTS_RESEARCH';
  select count(*),count(distinct claim_type) into claim_count,claim_types from public.dep_mlb_claims where run_id=new.run_id and game_id=new.game_id and superseded_at is null and claim_type in ('FAVORABLE_MECHANISM','ADVERSE_ROUTE','FULL_GAME_SYNTHESIS');
  select count(distinct phase_code) into art_count from public.dep_mlb_phase_artifacts where run_id=new.run_id and game_id=new.game_id and phase_code in ('F2','F3','F4','F5','F6','F7','F8','F9') and superseded_at is null;
  select count(*) into pass_count from public.dep_mlb_phase_state where run_id=new.run_id and phase_order between 0 and 9 and state='PASS';
  select exists(select 1 from public.dep_mlb_drive_artifacts d where d.run_id=new.run_id and d.game_id=new.game_id and d.drive_file_id=p.drive_file_id and d.content_hash=p.drive_hash and d.verified_readback=true and d.readback_tool_event_id is not null) into drive_ok;
  select min(first_pitch) into earliest_fp from public.dep_mlb_games where run_id=new.run_id and eligible_pregame;
  new.checks:=jsonb_build_object('derived_from_database_state',true,'tool_events_success',tool_count,'sports_evidence_count',evidence_count,'source_families',source_families,'source_origins',source_origins,'required_claims',claim_count,'required_claim_types',claim_types,'active_game_phase_artifacts',art_count,'expected_game_phase_artifacts',8,'f0_to_f9_pass_count',pass_count,'packet_frozen',p.frozen_at is not null,'packet_before_earliest_first_pitch',p.frozen_at is not null and earliest_fp is not null and p.frozen_at<earliest_fp,'drive_readback_event_attested',drive_ok);
  new.audit_status:=case when tool_count>=4 and evidence_count>=4 and source_families>=4 and source_origins>=2 and claim_count>=3 and claim_types=3 and art_count=8 and pass_count=10 and p.frozen_at is not null and earliest_fp is not null and p.frozen_at<earliest_fp and drive_ok then 'PASS' else 'FAIL' end;
  new.derived_by:='DATABASE_CONTROL_V05'; new.derived_at:=clock_timestamp();
  return new;
end $$;
drop trigger if exists dep_mlb_00_v05_process_audit_guard on public.dep_mlb_process_audits;
create trigger dep_mlb_00_v05_process_audit_guard before insert or update on public.dep_mlb_process_audits for each row execute function public.dep_mlb_v05_process_audit_guard();

-- The handoff guard is intentionally strict and final: max 2 PRIMARY, no POTENTIAL,
-- all audited packets, 100% closure, complete admission burden, verified Drive and Chat R1,
-- and terminal closure before earliest first pitch.
-- Its deployed definition is tracked in runtime/connected_v0_5/orchestrator_contract.json and Supabase production.

insert into public.dep_mlb_run_audit_verdicts(run_id,audit_version,verdict,reasons,sports_certification_valid)
values('DEP-MLB-20260819-REAL-1823-V04-A','POSTRUN_AUDIT_V05','FAIL',jsonb_build_array('TEMPORAL_INTEGRITY_FAIL','CANDIDATE_OVERBREADTH','FULL_GAME_SOURCE_DEPTH_INSUFFICIENT_FOR_SOME_GAMES'),false)
on conflict(run_id,audit_version) do update set verdict=excluded.verdict,reasons=excluded.reasons,sports_certification_valid=excluded.sports_certification_valid,created_at=clock_timestamp();
