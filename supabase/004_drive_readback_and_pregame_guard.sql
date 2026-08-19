create table if not exists public.dep_mlb_drive_artifacts (
  artifact_id uuid primary key default gen_random_uuid(),
  run_id text not null references public.dep_mlb_runs(run_id) on delete cascade,
  game_id text,
  artifact_type text not null check (artifact_type in ('RUN_DOSSIER','GAME_PACKET','HANDOFF_REPORT','AUDIT_REPORT')),
  drive_file_id text not null,
  content_hash text not null,
  verified_readback boolean not null default false,
  verification_source text,
  verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (run_id, game_id) references public.dep_mlb_games(run_id, game_id) on delete cascade,
  unique(run_id, game_id, artifact_type, drive_file_id, content_hash)
);

create index if not exists dep_mlb_drive_artifacts_lookup_idx on public.dep_mlb_drive_artifacts(run_id,game_id,drive_file_id,content_hash,verified_readback);

create or replace function public.dep_mlb_guard_drive_artifact_verification()
returns trigger language plpgsql as $$
begin
  if new.verified_readback then
    if new.verification_source <> 'GOOGLE_DRIVE_CONNECTOR' then raise exception 'DEP_MLB_DRIVE_VERIFICATION_SOURCE_INVALID'; end if;
    new.verified_at := coalesce(new.verified_at, now());
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_drive_artifact_verification_guard on public.dep_mlb_drive_artifacts;
create trigger dep_mlb_drive_artifact_verification_guard before insert or update on public.dep_mlb_drive_artifacts for each row execute function public.dep_mlb_guard_drive_artifact_verification();

create or replace function public.dep_mlb_validate_tool_event_game()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.dep_mlb_connector_registry c where c.connector_name=new.connector_name and c.current_state='VERIFIED_AVAILABLE') then
    raise exception 'DEP_MLB_CONNECTOR_NOT_VERIFIED_AVAILABLE';
  end if;
  if new.game_id is not null and not exists (select 1 from public.dep_mlb_games g where g.run_id = new.run_id and g.game_id = new.game_id) then
    raise exception 'DEP_MLB_TOOL_EVENT_GAME_RUN_MISMATCH';
  end if;
  return new;
end $$;

create or replace function public.dep_mlb_validate_evidence_lineage()
returns trigger language plpgsql as $$
declare t record; fp timestamptz;
begin
  select run_id, game_id, success into t from public.dep_mlb_tool_events where tool_event_id = new.tool_event_id;
  if not found then raise exception 'DEP_MLB_EVIDENCE_WITHOUT_TOOL_EVENT'; end if;
  if t.success is not true then raise exception 'DEP_MLB_EVIDENCE_FROM_FAILED_TOOL_EVENT'; end if;
  if t.run_id <> new.run_id or t.game_id is distinct from new.game_id then raise exception 'DEP_MLB_EVIDENCE_RUN_GAME_MISMATCH'; end if;
  if new.source_as_of is not null and new.captured_at < new.source_as_of then raise exception 'DEP_MLB_EVIDENCE_CAPTURE_BEFORE_SOURCE_AS_OF'; end if;
  select first_pitch into fp from public.dep_mlb_games where run_id=new.run_id and game_id=new.game_id;
  if new.evidence_scope='SPORTS_RESEARCH' and fp is not null then
    if new.captured_at >= fp then raise exception 'DEP_MLB_POST_FIRST_PITCH_CAPTURE_FORBIDDEN'; end if;
    if new.source_as_of is not null and new.source_as_of >= fp then raise exception 'DEP_MLB_POST_FIRST_PITCH_SOURCE_FORBIDDEN'; end if;
  end if;
  return new;
end $$;

create or replace function public.dep_mlb_guard_packet_freeze()
returns trigger language plpgsql as $$
begin
  if tg_op='UPDATE' and old.frozen_at is not null then
    if to_jsonb(new) - 'process_audit_status' <> to_jsonb(old) - 'process_audit_status' then raise exception 'DEP_MLB_FROZEN_PACKET_IMMUTABLE'; end if;
  end if;
  if new.frozen_at is not null then
    if new.packet_hash is null or length(new.packet_hash) < 32 then raise exception 'DEP_MLB_FREEZE_REQUIRES_PACKET_HASH'; end if;
    if new.drive_file_id is null or new.drive_hash is null then raise exception 'DEP_MLB_FREEZE_REQUIRES_DRIVE_ARTIFACT'; end if;
    if not exists (select 1 from public.dep_mlb_claims c where c.run_id=new.run_id and c.game_id=new.game_id) then raise exception 'DEP_MLB_FREEZE_REQUIRES_CLAIMS'; end if;
    if not exists (select 1 from public.dep_mlb_drive_artifacts d where d.run_id=new.run_id and d.game_id=new.game_id and d.drive_file_id=new.drive_file_id and d.content_hash=new.drive_hash and d.verified_readback=true and d.verification_source='GOOGLE_DRIVE_CONNECTOR') then
      raise exception 'DEP_MLB_FREEZE_REQUIRES_VERIFIED_DRIVE_READBACK';
    end if;
  end if;
  return new;
end $$;

create or replace function public.dep_mlb_validate_handoff()
returns trigger language plpgsql as $$
declare total_games integer; closed_games integer; good_packets integer;
begin
  select count(*) filter (where eligible_pregame), count(*) filter (where eligible_pregame and minimum_comparative_closure) into total_games, closed_games from public.dep_mlb_games where run_id=new.run_id;
  select count(distinct game_id) into good_packets from public.dep_mlb_game_packets where run_id=new.run_id and frozen_at is not null and process_audit_status='PASS' and drive_file_id is not null and drive_hash is not null;
  if new.validation_status='PASS' then
    if new.universe_game_count <> total_games or new.comparative_closed_count <> closed_games or total_games <> closed_games then raise exception 'DEP_MLB_HANDOFF_REQUIRES_100_PERCENT_COMPARATIVE_COVERAGE'; end if;
    if good_packets < total_games then raise exception 'DEP_MLB_HANDOFF_REQUIRES_VALID_PACKET_PER_GAME'; end if;
    if jsonb_array_length(new.primary_candidates) > 4 or jsonb_array_length(new.potential_candidates) > 2 then raise exception 'DEP_MLB_HANDOFF_CANDIDATE_CAP_EXCEEDED'; end if;
    if new.handoff_hash is null or new.drive_file_id is null or new.drive_hash is null then raise exception 'DEP_MLB_HANDOFF_REQUIRES_HASHED_DRIVE_ARTIFACT'; end if;
    if not exists (select 1 from public.dep_mlb_drive_artifacts d where d.run_id=new.run_id and d.game_id is null and d.artifact_type='HANDOFF_REPORT' and d.drive_file_id=new.drive_file_id and d.content_hash=new.drive_hash and d.verified_readback=true and d.verification_source='GOOGLE_DRIVE_CONNECTOR') then
      raise exception 'DEP_MLB_HANDOFF_REQUIRES_VERIFIED_DRIVE_READBACK';
    end if;
    new.validated_at := coalesce(new.validated_at, now());
  end if;
  return new;
end $$;

update public.agent_registry set metadata = metadata || jsonb_build_object('drive_readback_registry_required',true,'pregame_post_first_pitch_evidence_blocked',true,'connector_state_enforced_for_tool_events',true), updated_at=now() where agent_id='@DepuracionMLB';
