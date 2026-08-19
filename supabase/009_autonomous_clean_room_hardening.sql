-- DEP-MLB-KERNEL-0.3-AUTONOMOUS clean-room hardening.

create table if not exists public.dep_mlb_invocation_drive_receipts (
  invocation_id uuid primary key references public.dep_mlb_agent_invocations(invocation_id) on delete cascade,
  drive_folder_id text not null,
  report_drive_file_id text not null,
  verification_source text not null,
  verified_exists boolean not null default false,
  verified_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint dep_mlb_invocation_drive_source_check check (verification_source='GOOGLE_DRIVE_CONNECTOR'),
  constraint dep_mlb_invocation_drive_exists_check check (verified_exists=true)
);

create or replace function public.dep_mlb_guard_agent_invocation_clean_room()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  if exists(select 1 from public.dep_mlb_agent_invocations i where i.invocation_id<>new.invocation_id and (i.report_drive_file_id=new.report_drive_file_id or i.drive_folder_id=new.drive_folder_id)) then
    raise exception 'DEP_MLB_INVOCATION_REQUIRES_UNIQUE_DRIVE_ARTIFACTS';
  end if;
  if exists(select 1 from public.dep_mlb_runs r where r.report_drive_file_id=new.report_drive_file_id and (new.run_id is null or r.run_id<>new.run_id)) then
    raise exception 'DEP_MLB_INVOCATION_CANNOT_REUSE_PRIOR_RUN_REPORT';
  end if;
  if not new.clean_room or not new.no_prior_sports_reuse then raise exception 'DEP_MLB_INVOCATION_MUST_BE_CLEAN_ROOM'; end if;
  return new;
end $$;

drop trigger if exists dep_mlb_agent_invocation_clean_room_guard on public.dep_mlb_agent_invocations;
create trigger dep_mlb_agent_invocation_clean_room_guard before insert or update on public.dep_mlb_agent_invocations
for each row execute function public.dep_mlb_guard_agent_invocation_clean_room();

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
    if not exists(select 1 from public.dep_mlb_invocation_drive_receipts d where d.invocation_id=new.invocation_id and d.drive_folder_id=inv.drive_folder_id and d.report_drive_file_id=inv.report_drive_file_id and d.verified_exists=true and d.verification_source='GOOGLE_DRIVE_CONNECTOR') then
      raise exception 'DEP_MLB_AGENT_RUN_REQUIRES_VERIFIED_NEW_DRIVE_REPORT';
    end if;
  end if;
  return new;
end $$;

create or replace function public.dep_mlb_enforce_fresh_web_sports_evidence()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare av text; kv text; started timestamptz; conn text; requested timestamptz;
begin
  select agent_version,kernel_version,started_at into av,kv,started from public.dep_mlb_runs where run_id=new.run_id;
  if av='DEP-MLB-AGENT-1.1' or kv='DEP-MLB-KERNEL-0.3-AUTONOMOUS' then
    if new.evidence_scope='SPORTS_RESEARCH' then
      select connector_name,requested_at into conn,requested from public.dep_mlb_tool_events where tool_event_id=new.tool_event_id;
      if conn is distinct from 'Web' then raise exception 'DEP_MLB_SPORTS_EVIDENCE_REQUIRES_FRESH_WEB_TOOL_EVENT'; end if;
      if requested is null or requested<started then raise exception 'DEP_MLB_SPORTS_EVIDENCE_TOOL_EVENT_PREDATES_RUN'; end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_fresh_web_sports_evidence_guard on public.dep_mlb_evidence;
create trigger dep_mlb_fresh_web_sports_evidence_guard before insert or update on public.dep_mlb_evidence
for each row execute function public.dep_mlb_enforce_fresh_web_sports_evidence();

alter table public.dep_mlb_invocation_drive_receipts enable row level security;
