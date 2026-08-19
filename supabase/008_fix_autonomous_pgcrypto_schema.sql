-- Fix discovered by controlled valid-path test.
-- pgcrypto.digest lives in schema extensions while autonomous functions use hardened search_path.

create or replace function public.dep_mlb_init_phase_state()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
  if new.agent_version='DEP-MLB-AGENT-1.1' and new.kernel_version='DEP-MLB-KERNEL-0.3-AUTONOMOUS' then
    insert into public.dep_mlb_phase_state(run_id,phase_code,phase_order,state,owner,started_at,completed_at,completion_hash,gate_result,metadata)
    values
      (new.run_id,'F0',0,'PASS','KERNEL',now(),now(),encode(extensions.digest(new.run_id||'|F0|INVOCATION_BOUND','sha256'),'hex'),'PASS',jsonb_build_object('invocation_id',new.invocation_id,'execution_owner',new.execution_owner)),
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
    update public.dep_mlb_agent_invocations set status='BOUND_TO_RUN' where invocation_id=new.invocation_id;
  end if;
  return new;
end $$;

create or replace function public.dep_mlb_validate_phase_artifact()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare eid uuid; erun text; egame text;
begin
  if new.game_id is not null and not exists(select 1 from public.dep_mlb_games g where g.run_id=new.run_id and g.game_id=new.game_id) then
    raise exception 'DEP_MLB_PHASE_ARTIFACT_GAME_NOT_IN_RUN';
  end if;
  foreach eid in array new.evidence_ids loop
    select run_id,game_id into erun,egame from public.dep_mlb_evidence where evidence_id=eid;
    if not found then raise exception 'DEP_MLB_PHASE_ARTIFACT_EVIDENCE_NOT_FOUND'; end if;
    if erun<>new.run_id then raise exception 'DEP_MLB_PHASE_ARTIFACT_EVIDENCE_RUN_MISMATCH'; end if;
    if new.game_id is not null and egame<>new.game_id then raise exception 'DEP_MLB_PHASE_ARTIFACT_EVIDENCE_GAME_MISMATCH'; end if;
  end loop;
  if new.content_hash<>encode(extensions.digest(new.content::text,'sha256'),'hex') then raise exception 'DEP_MLB_PHASE_ARTIFACT_HASH_MISMATCH'; end if;
  return new;
end $$;
