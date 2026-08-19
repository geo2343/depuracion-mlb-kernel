-- Production migration: dep_mlb_kernel_05_isolate_v04_and_align_defaults

create or replace function public.dep_mlb_is_v04_run(p_run text)
returns boolean language sql stable set search_path to 'public','pg_temp' as $$
select exists(select 1 from public.dep_mlb_runs r where r.run_id=p_run and r.agent_version='DEP-MLB-AGENT-1.2' and r.kernel_version='DEP-MLB-KERNEL-0.4-AUTONOMOUS-REFACTOR');
$$;

create or replace function public.dep_mlb_guard_phase_artifact_immutability()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare r text; p text;
begin
  r:=coalesce(new.run_id,old.run_id); p:=coalesce(new.phase_code,old.phase_code);
  if (public.dep_mlb_is_v04_run(r) or public.dep_mlb_is_v05_run(r)) and exists(select 1 from public.dep_mlb_phase_state ps where ps.run_id=r and ps.phase_code=p and ps.state='PASS') then
    if not (tg_op='UPDATE' and old.superseded_at is null and new.superseded_at is not null and exists(select 1 from public.dep_mlb_reopen_events e where e.run_id=r and e.status='APPLYING' and public.dep_mlb_phase_order_of(p)>=public.dep_mlb_phase_order_of(e.reopen_from_phase))) then raise exception 'DEP_MLB_PASSED_PHASE_ARTIFACT_IMMUTABLE'; end if;
  end if;
  return coalesce(new,old);
end $$;

create or replace function public.dep_mlb_guard_handoff_immutability()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if tg_op in ('UPDATE','DELETE') and (public.dep_mlb_is_v04_run(old.run_id) or public.dep_mlb_is_v05_run(old.run_id)) and old.validation_status='PASS' then raise exception 'DEP_MLB_HANDOFF_IMMUTABLE_AFTER_PASS'; end if;
  return coalesce(new,old);
end $$;

create or replace function public.dep_mlb_v04_terminal_child_guard()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare r text;
begin
  r:=coalesce(new.run_id,old.run_id);
  if (public.dep_mlb_is_v04_run(r) or public.dep_mlb_is_v05_run(r)) and exists(select 1 from public.dep_mlb_runs where run_id=r and run_status='COMPLETED') then raise exception 'DEP_MLB_COMPLETED_RUN_CHILD_IMMUTABLE'; end if;
  return coalesce(new,old);
end $$;

create or replace function public.dep_mlb_validate_drive_artifact_v04()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare ev public.dep_mlb_tool_events%rowtype;
begin
  if public.dep_mlb_is_v04_run(new.run_id) or public.dep_mlb_is_v05_run(new.run_id) then
    if new.readback_tool_event_id is null then raise exception 'DEP_MLB_DRIVE_ARTIFACT_REQUIRES_READBACK_TOOL_EVENT'; end if;
    select * into ev from public.dep_mlb_tool_events where tool_event_id=new.readback_tool_event_id;
    if not found or ev.run_id<>new.run_id or ev.connector_name<>'Google_Drive' or not ev.success or ev.response_hash is null then raise exception 'DEP_MLB_DRIVE_READBACK_EVENT_INVALID'; end if;
    if ev.response_snapshot->>'drive_file_id'<>new.drive_file_id or ev.response_snapshot->>'content_hash'<>new.content_hash then raise exception 'DEP_MLB_DRIVE_READBACK_EVENT_HASH_OR_FILE_MISMATCH'; end if;
    new.verified_readback:=true; new.verification_source:='GOOGLE_DRIVE_CONNECTOR'; new.verified_at:=clock_timestamp();
  elsif new.verified_readback then
    if new.verification_source<>'GOOGLE_DRIVE_CONNECTOR' then raise exception 'DEP_MLB_DRIVE_VERIFICATION_SOURCE_INVALID'; end if;
    new.verified_at:=coalesce(new.verified_at,clock_timestamp());
  end if;
  return new;
end $$;

create or replace function public.dep_mlb_validate_chat_report()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare k text; req text[]:=array['slate_as_of','universe_comparative_coverage','depuration_core_mission_complete','primary_candidates','potential_candidates','best_excluded_game_id','best_excluded_reason','not_advanced_map','handoff_questions','direct_link','delivery_qa'];
begin
  if not (public.dep_mlb_is_v04_run(new.run_id) or public.dep_mlb_is_v05_run(new.run_id)) then return new; end if;
  if tg_op='UPDATE' and old.frozen_at is not null then raise exception 'DEP_MLB_CHAT_REPORT_IMMUTABLE_AFTER_FREEZE'; end if;
  foreach k in array req loop if not(new.content?k) then raise exception 'DEP_MLB_CHAT_REPORT_MISSING_FIELD:%',k; end if; end loop;
  if new.report_standard<>'MLB_CHAT_REPORT_STANDARD_R1' or new.created_by<>'AI_AGENT' then raise exception 'DEP_MLB_CHAT_REPORT_STANDARD_OR_OWNER_INVALID'; end if;
  if coalesce((new.content->>'depuration_core_mission_complete')::boolean,false) is not true then raise exception 'DEP_MLB_CHAT_REPORT_CORE_MISSION_NOT_PASS'; end if;
  if new.content->>'universe_comparative_coverage' not in ('100','100%','100.0','100.0%') then raise exception 'DEP_MLB_CHAT_REPORT_COVERAGE_NOT_100'; end if;
  if jsonb_typeof(new.content->'primary_candidates')<>'array' or jsonb_typeof(new.content->'potential_candidates')<>'array' or jsonb_typeof(new.content->'not_advanced_map')<>'object' or jsonb_typeof(new.content->'handoff_questions')<>'array' or jsonb_typeof(new.content->'delivery_qa')<>'object' then raise exception 'DEP_MLB_CHAT_REPORT_STRUCTURE_INVALID'; end if;
  if public.dep_mlb_is_v05_run(new.run_id) and (jsonb_array_length(new.content->'primary_candidates')>2 or jsonb_array_length(new.content->'potential_candidates')<>0) then raise exception 'DEP_MLB_V05_CHAT_MAX_TWO_PRIMARY_NO_POTENTIAL'; end if;
  if length(trim(new.content->>'direct_link'))<6 then raise exception 'DEP_MLB_CHAT_REPORT_DIRECT_LINK_REQUIRED'; end if;
  new.content_hash:=encode(extensions.digest(new.content::text,'sha256'),'hex'); new.qa_status:='PASS'; new.validated_at:=clock_timestamp();
  return new;
end $$;

alter table public.dep_mlb_runs alter column system_version set default 'DEP-MLB-V0.4';
alter table public.dep_mlb_runs alter column agent_version set default 'DEP-MLB-AGENT-1.3';
alter table public.dep_mlb_runs alter column kernel_version set default 'DEP-MLB-KERNEL-0.5-EXHAUSTIVE-SELECTIVE';
