-- Production migration: dep_mlb_kernel_05_fix_trace_immutability_table_dispatch
-- Prevent RECORD-field access on non-claim trace tables while retaining terminal/frozen immutability.

create or replace function public.dep_mlb_guard_trace_immutability()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare r text; g text; pc text;
begin
  if tg_op='INSERT' then
    r:=new.run_id; g:=new.game_id;
    if tg_table_name='dep_mlb_claims' then pc:=new.phase_code; end if;
  elsif tg_op='DELETE' then
    r:=old.run_id; g:=old.game_id;
    if tg_table_name='dep_mlb_claims' then pc:=old.phase_code; end if;
  else
    r:=coalesce(new.run_id,old.run_id); g:=coalesce(new.game_id,old.game_id);
    if tg_table_name='dep_mlb_claims' then pc:=coalesce(new.phase_code,old.phase_code); end if;
  end if;

  if public.dep_mlb_is_v04_run(r) or public.dep_mlb_is_v05_run(r) then
    if exists(select 1 from public.dep_mlb_runs x where x.run_id=r and x.run_status='COMPLETED') then
      raise exception 'DEP_MLB_COMPLETED_RUN_TRACE_IMMUTABLE';
    end if;
    if g is not null and exists(select 1 from public.dep_mlb_game_packets p where p.run_id=r and p.game_id=g and p.frozen_at is not null) then
      raise exception 'DEP_MLB_FROZEN_GAME_TRACE_IMMUTABLE';
    end if;
    if tg_table_name='dep_mlb_claims' and tg_op in ('UPDATE','DELETE') then
      if old.superseded_at is null
         and exists(select 1 from public.dep_mlb_phase_state ps where ps.run_id=r and ps.phase_code=pc and ps.state='PASS')
         and not exists(select 1 from public.dep_mlb_reopen_events e where e.run_id=r and e.status='APPLYING' and public.dep_mlb_phase_order_of(pc)>=public.dep_mlb_phase_order_of(e.reopen_from_phase)) then
        raise exception 'DEP_MLB_PASSED_PHASE_CLAIM_IMMUTABLE';
      end if;
    end if;
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
