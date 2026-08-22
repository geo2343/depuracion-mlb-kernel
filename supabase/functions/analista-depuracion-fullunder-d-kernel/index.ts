import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AGENT_ID = "@AnalistaDepuracionFullUnder_D";
const VERSION = "ANALISTADEPURACIONFULLUNDER-D-AGENT-1.2";
const KERNEL = "ANALISTADEPURACIONFULLUNDER-D-KERNEL-1.2-CONTROL-PLANE";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ outcome:"REJECTED", reason:"POST_REQUIRED" }, { status:405 });
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return Response.json({ outcome:"REJECTED", reason:"RUNTIME_CONFIGURATION_MISSING" }, { status:500 });
  const db = createClient(supabaseUrl, serviceKey, { auth:{ persistSession:false } });
  let body:any; try { body = await req.json(); } catch { return Response.json({ outcome:"REJECTED", reason:"INVALID_JSON" }, { status:400 }); }
  if (body?.agent_id != null && body.agent_id !== AGENT_ID) return Response.json({ outcome:"REJECTED", reason:"WRONG_AGENT_IDENTITY", expected:AGENT_ID }, { status:400 });
  const action = String(body?.action ?? "");
  const map: Record<string,[string,(b:any)=>Record<string,unknown>]> = {
    start_run:["fullunder_dep_d_start_run", b=>({p_upstream_agent_id:b.upstream_agent_id,p_upstream_run_id:b.upstream_run_id,p_upstream_packet_id:b.upstream_packet_id,p_upstream_packet_sha256:b.upstream_packet_sha256,p_upstream_as_of:b.upstream_as_of,p_slate_date:b.slate_date,p_test_mode:!!b.test_mode,p_idempotency_key:b.idempotency_key})],
    record_evidence:["fullunder_dep_d_record_evidence", b=>({p_run_id:b.run_id,p_requirement_id:b.requirement_id,p_game_key:b.game_key,p_evidence_type:b.evidence_type,p_source_ref:b.source_ref,p_source_sha256:b.source_sha256,p_as_of:b.as_of,p_detail:b.detail,p_payload:b.payload??{},p_expected_state_version:b.expected_state_version})],
    record_requirement:["fullunder_dep_d_record_requirement", b=>({p_run_id:b.run_id,p_requirement_id:b.requirement_id,p_status:b.status,p_execution_detail:b.execution_detail,p_expected_state_version:b.expected_state_version})],
    assess_candidate:["fullunder_dep_d_assess_candidate", b=>({p_run_id:b.run_id,p_game_key:b.game_key,p_disposition:b.disposition,p_causal_under_case:b.causal_under_case,p_adversarial_over_case:b.adversarial_over_case,p_uncertainty:b.uncertainty,p_missing_evidence:b.missing_evidence,p_flip_conditions:b.flip_conditions,p_rationale:b.rationale,p_evidence_ids:b.evidence_ids??[],p_confidence_label:b.confidence_label,p_expected_state_version:b.expected_state_version})],
    freeze_pre_dialogue:["fullunder_dep_d_freeze_pre_dialogue", b=>({p_run_id:b.run_id,p_expected_state_version:b.expected_state_version})],
    record_counterpart:["fullunder_dep_d_record_counterpart", b=>({p_run_id:b.run_id,p_peer_agent_id:b.peer_agent_id,p_peer_report_id:b.peer_report_id,p_peer_report_sha256:b.peer_report_sha256,p_convergence:b.convergence,p_divergence:b.divergence,p_material_effect:b.material_effect,p_expected_state_version:b.expected_state_version})],
    finalize_run:["fullunder_dep_d_finalize_run", b=>({p_run_id:b.run_id,p_expected_state_version:b.expected_state_version})],
    create_handoff:["fullunder_dep_d_create_handoff", b=>({p_run_id:b.run_id,p_target_agent_id:b.target_agent_id,p_payload:b.payload??{},p_expected_state_version:b.expected_state_version})]
  };
  const spec=map[action]; if(!spec) return Response.json({outcome:"REJECTED",reason:"UNKNOWN_ACTION",agent_id:AGENT_ID,version:VERSION,kernel:KERNEL},{status:400});
  const [rpc,argsFn]=spec; const {data,error}=await db.rpc(rpc,argsFn(body));
  if(error) return Response.json({outcome:"REJECTED",reason:"KERNEL_RPC_ERROR",detail:error.message,agent_id:AGENT_ID,version:VERSION,kernel:KERNEL},{status:400});
  return Response.json({outcome:"ACCEPTED",agent_id:AGENT_ID,version:VERSION,kernel:KERNEL,action,result:data});
});