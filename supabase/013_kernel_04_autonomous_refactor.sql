-- Canonical source record for the applied Supabase migration series:
-- 20260819212507 dep_mlb_kernel_04_autonomous_refactor
-- 20260819213334 dep_mlb_kernel_04_audit_closure
-- 20260819213614 dep_mlb_kernel_04_fix_handoff_gid_ambiguity
-- 20260819214042 dep_mlb_kernel_04_terminal_trace_seal
--
-- This file records the final intended Agent 1.2 / Kernel 0.4 schema contract.
-- Methodological authority remains Mother V0.3; Kernel enforcement only.

alter table public.dep_mlb_runs alter column agent_version set default 'DEP-MLB-AGENT-1.2';
alter table public.dep_mlb_runs alter column kernel_version set default 'DEP-MLB-KERNEL-0.4-AUTONOMOUS-REFACTOR';
alter table public.dep_mlb_phase_artifacts add column if not exists tool_event_ids uuid[] not null default '{}'::uuid[];
alter table public.dep_mlb_phase_artifacts add column if not exists superseded_at timestamptz;
alter table public.dep_mlb_claims add column if not exists phase_code text;
alter table public.dep_mlb_claims add column if not exists superseded_at timestamptz;
alter table public.dep_mlb_tool_events add column if not exists response_snapshot jsonb not null default '{}'::jsonb;
alter table public.dep_mlb_drive_artifacts add column if not exists readback_tool_event_id uuid references public.dep_mlb_tool_events(tool_event_id) on delete restrict;
alter table public.dep_mlb_invocation_drive_receipts add column if not exists verification_event_id uuid;
alter table public.dep_mlb_evidence add column if not exists tool_response_hash text;
alter table public.dep_mlb_handoffs add column if not exists core_mission_complete boolean not null default false;
alter table public.dep_mlb_handoffs add column if not exists drive_report_complete boolean not null default false;
alter table public.dep_mlb_handoffs add column if not exists chat_report_complete boolean not null default false;
alter table public.dep_mlb_handoffs add column if not exists delivery_status text not null default 'INCOMPLETE';
alter table public.dep_mlb_handoffs add column if not exists chat_report_hash text;

create table if not exists public.dep_mlb_invocation_connector_events (
  event_id uuid primary key default gen_random_uuid(),
  invocation_id uuid not null references public.dep_mlb_agent_invocations(invocation_id) on delete cascade,
  connector_name text not null,
  operation text not null,
  resource_id text not null,
  resource_url text,
  response_snapshot jsonb not null,
  response_hash text not null,
  success boolean not null default true,
  requested_at timestamptz not null default now(),
  completed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
alter table public.dep_mlb_invocation_connector_events enable row level security;

create table if not exists public.dep_mlb_chat_reports (
  run_id text primary key references public.dep_mlb_runs(run_id) on delete cascade,
  report_standard text not null default 'MLB_CHAT_REPORT_STANDARD_R1',
  content jsonb not null,
  content_hash text not null,
  qa_status text not null default 'PENDING',
  created_by text not null default 'AI_AGENT',
  prepared_at timestamptz not null default now(),
  validated_at timestamptz,
  frozen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  check (report_standard='MLB_CHAT_REPORT_STANDARD_R1'),
  check (qa_status in ('PENDING','PASS','FAIL')),
  check (created_by='AI_AGENT')
);
alter table public.dep_mlb_chat_reports enable row level security;

create table if not exists public.dep_mlb_reopen_events (
  reopen_id uuid primary key default gen_random_uuid(),
  run_id text not null references public.dep_mlb_runs(run_id) on delete cascade,
  game_id text,
  trigger_type text not null,
  reopen_from_phase text not null,
  source_tool_event_id uuid not null references public.dep_mlb_tool_events(tool_event_id) on delete restrict,
  reason text not null,
  status text not null default 'CREATED',
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  check (reopen_from_phase in ('F1','F2','F3','F4','F6','F7')),
  check (status in ('CREATED','APPLYING','APPLIED','REJECTED')),
  check (trigger_type in ('IDENTITY_CHANGE','STARTER_CHANGE','LINEUP_MATERIAL_CHANGE','BULLPEN_CONTEXT_CHANGE','DISCRIMINANT_UPDATE','FULL_GAME_TRANSITION_CHANGE'))
);
alter table public.dep_mlb_reopen_events enable row level security;

create unique index if not exists dep_mlb_phase_artifact_one_active
on public.dep_mlb_phase_artifacts(run_id,coalesce(game_id,'__SLATE__'),phase_code,artifact_type)
where superseded_at is null;

-- Final 0.4 enforcement invariants implemented in Supabase and verified by controlled E2E:
-- 1) F2-F5 target ALL eligible games.
-- 2) F6 only F5=DISCRIMINANT.
-- 3) F7-F8 only survivors.
-- 4) F9 returns to all games + horizontal audit.
-- 5) sports evidence requires fresh Web lineage with source URL/origin/as_of + DB hashes.
-- 6) Drive verification requires linked Google Drive tool event.
-- 7) packet hashes and process audits are database-derived.
-- 8) pre-F9 material changes selectively reopen owner phase + downstream; old artifacts use superseded_at.
-- 9) post-F9 material sports change requires a new clean-room run.
-- 10) F10 requires RUN_DOSSIER + HANDOFF_REPORT + typed handoff + frozen CHAT R1 + DELIVERY_STATUS=COMPLETE.
-- 11) completed run trace and PASS handoff are immutable.
--
-- The live database function bodies are authoritative and were read back after application.
-- See docs/AUDIT_KERNEL_04.md for physical validation evidence and exact registered tests.
