-- @DepuracionMLB connected-agent persistence and chain of custody
-- Methodological authority: @DepuracionMLB Constitution V0.3

create table if not exists public.dep_mlb_runs (
  run_id text primary key,
  agent_id text not null default '@DepuracionMLB',
  system_version text not null default 'DEP-MLB-V0.3',
  agent_version text not null default 'DEP-MLB-AGENT-1.0',
  kernel_version text not null default 'DEP-MLB-KERNEL-0.2-CONNECTED',
  run_status text not null default 'NEW' check (run_status in ('NEW','IN_PROGRESS','CONDITIONED','WAITING_FOR_MATERIAL_UPDATE','COMPLETED','AUDIT_ONLY','DEPURATION_INCOMPLETE')),
  run_mode text not null default 'CONNECTED_RESEARCH' check (run_mode in ('CONNECTED_RESEARCH','CONTROLLED_VALIDATION','AUDIT_ONLY','PROTOTYPE_SIMULATION')),
  snapshot_as_of timestamptz,
  universe_frozen_at timestamptz,
  universe_hash text,
  report_drive_file_id text unique,
  report_drive_hash text,
  started_at timestamptz not null default now(),
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dep_mlb_games (
  run_id text not null references public.dep_mlb_runs(run_id) on delete cascade,
  game_id text not null,
  away_team text not null,
  home_team text not null,
  first_pitch timestamptz,
  venue text,
  game_status text,
  eligible_pregame boolean not null default true,
  minimum_comparative_closure boolean not null default false,
  final_classification text check (final_classification is null or final_classification in ('PRIMARY_CANDIDATE','POTENTIAL_CANDIDATE','NOT_ADVANCED','WAITING_FOR_MATERIAL_UPDATE','DEPURATION_INCOMPLETE')),
  snapshot_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (run_id, game_id)
);

create table if not exists public.dep_mlb_tool_events (
  tool_event_id uuid primary key default gen_random_uuid(),
  run_id text not null,
  game_id text,
  connector_name text not null,
  operation text not null,
  source_url text,
  source_origin text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  source_as_of timestamptz,
  response_hash text,
  success boolean not null default true,
  error_code text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (run_id) references public.dep_mlb_runs(run_id) on delete cascade,
  foreign key (run_id, game_id) references public.dep_mlb_games(run_id, game_id) on delete cascade
);

create table if not exists public.dep_mlb_evidence (
  evidence_id uuid primary key default gen_random_uuid(),
  run_id text not null,
  game_id text not null,
  tool_event_id uuid not null references public.dep_mlb_tool_events(tool_event_id) on delete restrict,
  source_family text not null,
  source_origin text not null,
  source_url text,
  captured_at timestamptz not null default now(),
  source_as_of timestamptz,
  snapshot_hash text not null,
  snapshot jsonb not null default '{}'::jsonb,
  evidence_scope text not null default 'SPORTS_RESEARCH',
  material boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (run_id, game_id) references public.dep_mlb_games(run_id, game_id) on delete cascade
);

create table if not exists public.dep_mlb_claims (
  claim_id uuid primary key default gen_random_uuid(),
  run_id text not null,
  game_id text not null,
  claim_type text not null,
  claim_text text not null,
  evidence_ids uuid[] not null,
  created_at timestamptz not null default now(),
  foreign key (run_id, game_id) references public.dep_mlb_games(run_id, game_id) on delete cascade,
  check (cardinality(evidence_ids) > 0)
);

create table if not exists public.dep_mlb_game_packets (
  packet_id uuid primary key default gen_random_uuid(),
  run_id text not null,
  game_id text not null,
  packet_version integer not null default 1 check (packet_version >= 1),
  phase_reached text,
  depth_mode text check (depth_mode is null or depth_mode in ('STOP','STANDARD','DISCRIMINANT')),
  governing_architecture text not null,
  strongest_countercase text not null,
  material_uncertainties text not null,
  advancement_reason text not null,
  change_condition text not null,
  research_stop_reason text not null,
  reasoning jsonb not null default '{}'::jsonb,
  classification text not null check (classification in ('PRIMARY_CANDIDATE','POTENTIAL_CANDIDATE','NOT_ADVANCED','WAITING_FOR_MATERIAL_UPDATE','DEPURATION_INCOMPLETE')),
  previous_packet_hash text,
  packet_hash text,
  frozen_at timestamptz,
  drive_file_id text,
  drive_hash text,
  process_audit_status text not null default 'PENDING' check (process_audit_status in ('PENDING','PASS','FAIL')),
  created_at timestamptz not null default now(),
  foreign key (run_id, game_id) references public.dep_mlb_games(run_id, game_id) on delete cascade,
  unique (run_id, game_id, packet_version)
);

create table if not exists public.dep_mlb_process_audits (
  audit_id uuid primary key default gen_random_uuid(),
  run_id text not null,
  game_id text not null,
  packet_id uuid not null unique references public.dep_mlb_game_packets(packet_id) on delete cascade,
  audit_status text not null check (audit_status in ('PASS','FAIL')),
  checks jsonb not null,
  derived_by text not null default 'DATABASE_CONTROL',
  derived_at timestamptz not null default now(),
  foreign key (run_id, game_id) references public.dep_mlb_games(run_id, game_id) on delete cascade
);

create table if not exists public.dep_mlb_handoffs (
  run_id text primary key references public.dep_mlb_runs(run_id) on delete cascade,
  universe_game_count integer not null check (universe_game_count >= 0),
  comparative_closed_count integer not null check (comparative_closed_count >= 0),
  primary_candidates jsonb not null default '[]'::jsonb,
  potential_candidates jsonb not null default '[]'::jsonb,
  best_excluded_game_id text,
  comparison_last_vs_best_excluded text,
  handoff_hash text,
  drive_file_id text,
  drive_hash text,
  validation_status text not null default 'PENDING' check (validation_status in ('PENDING','PASS','FAIL')),
  validated_at timestamptz,
  frozen_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.dep_mlb_connector_registry (
  connector_name text primary key,
  role text not null,
  required boolean not null default true,
  current_state text not null check (current_state in ('VERIFIED_AVAILABLE','AVAILABLE_NOT_BOUND','NOT_VISIBLE','NOT_REQUIRED','BLOCKED')),
  last_verified_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create or replace function public.dep_mlb_validate_tool_event_game()
returns trigger language plpgsql as $$
begin
  if new.game_id is not null and not exists (
    select 1 from public.dep_mlb_games g where g.run_id = new.run_id and g.game_id = new.game_id
  ) then raise exception 'DEP_MLB_TOOL_EVENT_GAME_RUN_MISMATCH'; end if;
  return new;
end $$;

drop trigger if exists dep_mlb_tool_event_game_guard on public.dep_mlb_tool_events;
create trigger dep_mlb_tool_event_game_guard before insert or update on public.dep_mlb_tool_events for each row execute function public.dep_mlb_validate_tool_event_game();

create or replace function public.dep_mlb_validate_evidence_lineage()
returns trigger language plpgsql as $$
declare t record;
begin
  select run_id, game_id, success into t from public.dep_mlb_tool_events where tool_event_id = new.tool_event_id;
  if not found then raise exception 'DEP_MLB_EVIDENCE_WITHOUT_TOOL_EVENT'; end if;
  if t.success is not true then raise exception 'DEP_MLB_EVIDENCE_FROM_FAILED_TOOL_EVENT'; end if;
  if t.run_id <> new.run_id or t.game_id is distinct from new.game_id then raise exception 'DEP_MLB_EVIDENCE_RUN_GAME_MISMATCH'; end if;
  if new.source_as_of is not null and new.captured_at < new.source_as_of then raise exception 'DEP_MLB_EVIDENCE_CAPTURE_BEFORE_SOURCE_AS_OF'; end if;
  return new;
end $$;

drop trigger if exists dep_mlb_evidence_lineage_guard on public.dep_mlb_evidence;
create trigger dep_mlb_evidence_lineage_guard before insert or update on public.dep_mlb_evidence for each row execute function public.dep_mlb_validate_evidence_lineage();

create or replace function public.dep_mlb_validate_claim_evidence()
returns trigger language plpgsql as $$
declare eid uuid;
begin
  foreach eid in array new.evidence_ids loop
    if not exists (select 1 from public.dep_mlb_evidence e where e.evidence_id=eid and e.run_id=new.run_id and e.game_id=new.game_id) then
      raise exception 'DEP_MLB_CLAIM_EVIDENCE_RUN_GAME_MISMATCH';
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists dep_mlb_claim_evidence_guard on public.dep_mlb_claims;
create trigger dep_mlb_claim_evidence_guard before insert or update on public.dep_mlb_claims for each row execute function public.dep_mlb_validate_claim_evidence();

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
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_packet_freeze_guard on public.dep_mlb_game_packets;
create trigger dep_mlb_packet_freeze_guard before insert or update on public.dep_mlb_game_packets for each row execute function public.dep_mlb_guard_packet_freeze();

create or replace function public.dep_mlb_sync_packet_audit()
returns trigger language plpgsql as $$
begin
  update public.dep_mlb_game_packets set process_audit_status = new.audit_status where packet_id = new.packet_id;
  return new;
end $$;

drop trigger if exists dep_mlb_sync_packet_audit_trigger on public.dep_mlb_process_audits;
create trigger dep_mlb_sync_packet_audit_trigger after insert or update on public.dep_mlb_process_audits for each row execute function public.dep_mlb_sync_packet_audit();

create or replace function public.dep_mlb_validate_handoff()
returns trigger language plpgsql as $$
declare total_games integer; closed_games integer; good_packets integer;
begin
  select count(*) filter (where eligible_pregame), count(*) filter (where eligible_pregame and minimum_comparative_closure)
  into total_games, closed_games from public.dep_mlb_games where run_id=new.run_id;
  select count(distinct game_id) into good_packets from public.dep_mlb_game_packets
  where run_id=new.run_id and frozen_at is not null and process_audit_status='PASS' and drive_file_id is not null and drive_hash is not null;
  if new.validation_status='PASS' then
    if new.universe_game_count <> total_games or new.comparative_closed_count <> closed_games or total_games <> closed_games then raise exception 'DEP_MLB_HANDOFF_REQUIRES_100_PERCENT_COMPARATIVE_COVERAGE'; end if;
    if good_packets < total_games then raise exception 'DEP_MLB_HANDOFF_REQUIRES_VALID_PACKET_PER_GAME'; end if;
    if jsonb_array_length(new.primary_candidates) > 4 or jsonb_array_length(new.potential_candidates) > 2 then raise exception 'DEP_MLB_HANDOFF_CANDIDATE_CAP_EXCEEDED'; end if;
    if new.handoff_hash is null or new.drive_file_id is null or new.drive_hash is null then raise exception 'DEP_MLB_HANDOFF_REQUIRES_HASHED_DRIVE_ARTIFACT'; end if;
    new.validated_at := coalesce(new.validated_at, now());
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_handoff_guard on public.dep_mlb_handoffs;
create trigger dep_mlb_handoff_guard before insert or update on public.dep_mlb_handoffs for each row execute function public.dep_mlb_validate_handoff();

insert into public.dep_mlb_connector_registry(connector_name, role, required, current_state, metadata) values
('Web','public MLB/source research and current information',true,'VERIFIED_AVAILABLE','{"bridge":"ChatGPT web connector"}'::jsonb),
('Google_Drive','canonical authority, run dossiers and handoff artifacts',true,'VERIFIED_AVAILABLE','{"root_folder_id":"1N8r-rn51Cj2kokFxIzasvhIlH6P1-x4i"}'::jsonb),
('GitHub','versioned runtime, manifests, migrations and tests',true,'VERIFIED_AVAILABLE','{"repository":"geo2343/depuracion-mlb-kernel"}'::jsonb),
('Supabase','durable state, lineage, enforcement and audit',true,'VERIFIED_AVAILABLE','{"project_id":"yejaollmavoudbxnbpll"}'::jsonb),
('Vercel','optional standalone HTTP runtime/deployment',false,'NOT_VISIBLE','{"team_id":"team_WYzZX77y9JwWZLF7LIN0ABec","observed_projects":0}'::jsonb)
on conflict (connector_name) do update set role=excluded.role, required=excluded.required, current_state=excluded.current_state, last_verified_at=now(), metadata=excluded.metadata;

insert into public.agent_registry(agent_id,agent_version,status,protocol_id,system_version,kernel_version,mother_document_sha256,manifest_path,activation_aliases,manual_phase_authorization_required,auto_advance,drive_root_folder_id,drive_execution_folder_id,drive_authority_folder_id,real_money_authority,metadata)
values('@DepuracionMLB','DEP-MLB-AGENT-1.0','ACTIVE','DEPURACION_MLB_V0_3_PROGRESSIVE','DEP-MLB-V0.3','DEP-MLB-KERNEL-0.2-CONNECTED','b258d6b43348cd3a1cba8ba515e6512a91cc3eb80d5447bd5d80c56a6fec835d','agents/depuracion_mlb_agent.json',array['@DepuracionMLB','@MLBdepuración','@MLBdepuracion','ejecuta @DepuracionMLB','ejecutar MLB depuración'],false,true,'1N8r-rn51Cj2kokFxIzasvhIlH6P1-x4i','1dniT0sZmGgLmp0m-aBqvfCMhZq-Ylqhx','1A0wV2KYzHuw541ndGF73Gt-hdTmUJztN',false,jsonb_build_object('canonical_mother_document_id','1nod0j35fZeILy7fxUk5IPCT7_qn3f0sEFsxmLbDdfrA','canonical_mother_version','V0.3','mother_hash_basis','plain-text export verified 2026-08-19','uploaded_historical_document_sha256','855236ea11082458da8e1ca7e05ac446070a107bee45f51abdd0866279dc7a00','uploaded_historical_document_authority','NON_OPERATIVE_REFERENCE_ONLY','runtime_predecessor','V0.1 PROTOTYPE_SIMULATION','market_scope','MLB FULL GAME UNDER PREGAME depuration only','betting_authority',false,'handoff_target','@iainvestigadora','max_primary',4,'max_potential',2,'full_universe_minimum_comparative_closure_required',true,'uncertainty_is_not_automatic_adversity',true,'score_voting_forbidden',true,'standalone_vercel_deployment_verified',false))
on conflict (agent_id) do update set agent_version=excluded.agent_version,status=excluded.status,protocol_id=excluded.protocol_id,system_version=excluded.system_version,kernel_version=excluded.kernel_version,mother_document_sha256=excluded.mother_document_sha256,manifest_path=excluded.manifest_path,activation_aliases=excluded.activation_aliases,manual_phase_authorization_required=excluded.manual_phase_authorization_required,auto_advance=excluded.auto_advance,drive_root_folder_id=excluded.drive_root_folder_id,drive_execution_folder_id=excluded.drive_execution_folder_id,drive_authority_folder_id=excluded.drive_authority_folder_id,real_money_authority=excluded.real_money_authority,metadata=excluded.metadata,updated_at=now();

create index if not exists dep_mlb_tool_events_run_game_idx on public.dep_mlb_tool_events(run_id,game_id,created_at);
create index if not exists dep_mlb_evidence_run_game_idx on public.dep_mlb_evidence(run_id,game_id,captured_at);
create index if not exists dep_mlb_claims_run_game_idx on public.dep_mlb_claims(run_id,game_id,created_at);
create index if not exists dep_mlb_packets_run_game_idx on public.dep_mlb_game_packets(run_id,game_id,packet_version);
