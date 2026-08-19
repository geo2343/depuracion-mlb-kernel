-- DEP-MLB-KERNEL-0.3-AUTONOMOUS
-- Semantic completeness gates + automatic terminal closure.
-- Applied physically to Supabase as dep_mlb_autonomous_phase_semantics_and_closure.

-- dep_mlb_validate_phase_artifact now enforces exact artifact type per phase:
-- F2 STARTER_SCREEN
-- F3 OFFENSE_SCREEN
-- F4 BULLPEN_CONTEXT_SCREEN
-- F5 STRUCTURAL_CROSS
-- F6 DISCRIMINANT_RESOLUTION
-- F7 FULL_GAME_VIABILITY
-- F8 MATERIALIZATION_COUNTERCASE
-- F9 RED_TEAM_RESULT (game) / HORIZONTAL_AUDIT (slate)
-- It also requires evidence lineage, non-empty reasoning, phase-specific semantic fields,
-- AI_AGENT creator identity and SHA-256 content integrity.

-- dep_mlb_phase_gate now counts only the correct artifact type for 100% eligible-game coverage.
-- F9 additionally requires one slate-level HORIZONTAL_AUDIT.
-- F10 requires a database-validated handoff and one frozen process-audited packet per eligible game.

create or replace function public.dep_mlb_guard_autonomous_run_close()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare f10 text;
begin
  if (new.agent_version='DEP-MLB-AGENT-1.1' or new.kernel_version='DEP-MLB-KERNEL-0.3-AUTONOMOUS')
     and (new.run_status='COMPLETED' or new.orchestration_status='COMPLETED') then
    select state into f10 from public.dep_mlb_phase_state where run_id=new.run_id and phase_code='F10';
    if f10 is distinct from 'PASS' then raise exception 'DEP_MLB_AUTONOMOUS_RUN_CLOSE_REQUIRES_F10_PASS'; end if;
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_autonomous_run_close_guard on public.dep_mlb_runs;
create trigger dep_mlb_autonomous_run_close_guard before update on public.dep_mlb_runs
for each row execute function public.dep_mlb_guard_autonomous_run_close();

create or replace function public.dep_mlb_sync_orchestration_state()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare inv uuid; next_phase text;
begin
  select invocation_id into inv from public.dep_mlb_runs where run_id=new.run_id;
  if new.state='IN_PROGRESS' then
    update public.dep_mlb_runs set run_status='IN_PROGRESS',orchestration_status='EXECUTING',phase_cursor=new.phase_code,updated_at=now() where run_id=new.run_id;
    update public.dep_mlb_agent_invocations set status='EXECUTING' where invocation_id=inv;
  elsif new.state='PASS' then
    if new.phase_code='F10' then
      update public.dep_mlb_runs set run_status='COMPLETED',orchestration_status='COMPLETED',phase_cursor='F10',closed_at=now(),updated_at=now() where run_id=new.run_id;
      update public.dep_mlb_agent_invocations set status='COMPLETED' where invocation_id=inv;
    else
      select phase_code into next_phase from public.dep_mlb_phase_state where run_id=new.run_id and phase_order=new.phase_order+1;
      update public.dep_mlb_runs set orchestration_status='READY_FOR_NEXT_PHASE',phase_cursor=coalesce(next_phase,new.phase_code),updated_at=now() where run_id=new.run_id;
    end if;
  elsif new.state='FAIL' then
    update public.dep_mlb_runs set orchestration_status='BLOCKED',phase_cursor=new.phase_code,updated_at=now() where run_id=new.run_id;
  end if;
  return new;
end $$;

drop trigger if exists dep_mlb_sync_orchestration_state_trigger on public.dep_mlb_phase_state;
create trigger dep_mlb_sync_orchestration_state_trigger after update on public.dep_mlb_phase_state
for each row execute function public.dep_mlb_sync_orchestration_state();
