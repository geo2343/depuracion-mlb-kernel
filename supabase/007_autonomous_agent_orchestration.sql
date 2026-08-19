-- DEP-MLB-KERNEL-0.3-AUTONOMOUS
-- Mirrors migration dep_mlb_autonomous_agent_orchestration applied to Supabase.

create table if not exists public.dep_mlb_agent_invocations (
  invocation_id uuid primary key default gen_random_uuid(),
  invoked_alias text not null,
  invoked_at timestamptz not null default now(),
  target_date date,
  invocation_source text not null default 'CHATGPT_ALIAS',
  autonomy_mode text not null default 'FULL_AGENT',
  status text not null default 'CREATED',
  run_id text unique,
  drive_folder_id text not null,
  report_drive_file_id text not null,
  authority_sha256 text not null,
  agent_version text not null,
  kernel_version text not null,
  protocol_id text not null,
  clean_room boolean not null default true,
  no_prior_sports_reuse boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

alter table public.dep_mlb_runs add column if not exists invocation_id uuid references public.dep_mlb_agent_invocations(invocation_id);
alter table public.dep_mlb_runs add column if not exists execution_owner text;
alter table public.dep_mlb_runs add column if not exists orchestration_status text;
alter table public.dep_mlb_runs add column if not exists phase_cursor text;
alter table public.dep_mlb_runs alter column agent_version set default 'DEP-MLB-AGENT-1.1';
alter table public.dep_mlb_runs alter column kernel_version set default 'DEP-MLB-KERNEL-0.3-AUTONOMOUS';

create table if not exists public.dep_mlb_phase_state (
  run_id text not null references public.dep_mlb_runs(run_id) on delete cascade,
  phase_code text not null,
  phase_order integer not null,
  state text not null default 'PENDING',
  owner text not null,
  started_at timestamptz,
  completed_at timestamptz,
  completion_hash text,
  gate_result text not null default 'PENDING',
  metadata jsonb not null default '{}'::jsonb,
  primary key(run_id,phase_code)
);

create table if not exists public.dep_mlb_phase_artifacts (
  artifact_id uuid primary key default gen_random_uuid(),
  run_id text not null references public.dep_mlb_runs(run_id) on delete cascade,
  game_id text,
  phase_code text not null,
  artifact_type text not null,
  content jsonb not null,
  evidence_ids uuid[] not null default '{}'::uuid[],
  content_hash text not null,
  created_by text not null default 'AI_AGENT',
  created_at timestamptz not null default now(),
  foreign key(run_id,game_id) references public.dep_mlb_games(run_id,game_id) on delete cascade
);

create or replace function public.dep_mlb_validate_agent_run_origin()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare inv public.dep_mlb_agent_invocations%rowtype;
begin
  if new.agent_version='DEP-MLB-AGENT-1.1' or new.kernel_version='DEP-MLB-KERNEL-0.3-AUTONOMOUS' then
    if new.invocation_id is null then raise exception 'DEP_MLB_AGENT_RUN_REQUIRES_INVOCATION'; end if;
    select * into inv from public.dep_mlb_agent_invocations where invocation_id=new.invocation_id;
    if not found then raise exception 'DEP_MLB_INVOCATION_NOT_FOUND'; end if;
    if inv.run_id is distinct from new.run_id then raise exception 'DEP_MLB_INVOCATION_RUN_ID_MISMATCH'; end if;
    if inv.autonomy_mode<>'FULL_AGENT' or inv.invocation_source<>'CHATGPT_ALIAS' then raise exception 'DEP_MLB_AGENT_RUN_REQUIRES_FULL_AGENT_ALIAS_INVOCATION'; end if;
    if not inv.clean_room or not inv.no_prior_sports_reuse then raise exception 'DEP_MLB_AGENT_RUN_REQUIRES_CLEAN_ROOM'; end if;
    if inv.report_drive_file_id is distinct from new.report_drive_file_id then raise exception 'DEP_MLB_INVOCATION_REPORT_MISMATCH'; end if;
    if new.execution_owner is distinct from 'AI_AGENT_ORCHESTRATOR' then raise exception 'DEP_MLB_AGENT_RUN_REQUIRES_ORCHESTRATOR_OWNER'; end if;
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_agent_run_origin_guard on public.dep_mlb_runs;
create trigger dep_mlb_agent_run_origin_guard before insert or update on public.dep_mlb_runs
for each row execute function public.dep_mlb_validate_agent_run_origin();

create or replace function public.dep_mlb_init_phase_state()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  if new.agent_version='DEP-MLB-AGENT-1.1' and new.kernel_version='DEP-MLB-KERNEL-0.3-AUTONOMOUS' then
    insert into public.dep_mlb_phase_state(run_id,phase_code,phase_order,state,owner,started_at,completed_at,completion_hash,gate_result,metadata)
    values
      (new.run_id,'F0',0,'PASS','KERNEL',now(),now(),encode(extensions.digest(new.run_id||'|F0|INVOCATION_BOUND','sha256'),'hex'),'PASS',jsonb_build_object('invocation_id',new.invocation_id)),
      (new.run_id,'F1',1,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F2',2,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F3',3,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F4',4,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F5',5,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F6',6,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F7',7,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F8',8,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F9',9,'PENDING','AI_AGENT',null,null,null,'PENDING','{}'),
      (new.run_id,'F10',10,'PENDING','AI_AGENT',null,null,null,'PENDING','{}')
    on conflict do nothing;
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_init_phase_state_trigger on public.dep_mlb_runs;
create trigger dep_mlb_init_phase_state_trigger after insert on public.dep_mlb_runs
for each row execute function public.dep_mlb_init_phase_state();

create or replace function public.dep_mlb_validate_phase_artifact()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare eid uuid; erun text; egame text;
begin
  foreach eid in array new.evidence_ids loop
    select run_id,game_id into erun,egame from public.dep_mlb_evidence where evidence_id=eid;
    if not found then raise exception 'DEP_MLB_PHASE_ARTIFACT_EVIDENCE_NOT_FOUND'; end if;
    if erun<>new.run_id then raise exception 'DEP_MLB_PHASE_ARTIFACT_EVIDENCE_RUN_MISMATCH'; end if;
    if new.game_id is not null and egame<>new.game_id then raise exception 'DEP_MLB_PHASE_ARTIFACT_EVIDENCE_GAME_MISMATCH'; end if;
  end loop;
  if new.content_hash<>encode(extensions.digest(new.content::text,'sha256'),'hex') then raise exception 'DEP_MLB_PHASE_ARTIFACT_HASH_MISMATCH'; end if;
  return new;
end $$;

drop trigger if exists dep_mlb_phase_artifact_guard on public.dep_mlb_phase_artifacts;
create trigger dep_mlb_phase_artifact_guard before insert or update on public.dep_mlb_phase_artifacts
for each row execute function public.dep_mlb_validate_phase_artifact();

-- The live database also contains dep_mlb_phase_gate and dep_mlb_handoff_requires_agent_f10,
-- enforcing F0→F10 order, 100% game artifact coverage, F9 horizontal audit and F10 validated handoff.

alter table public.dep_mlb_agent_invocations enable row level security;
alter table public.dep_mlb_phase_state enable row level security;
alter table public.dep_mlb_phase_artifacts enable row level security;
