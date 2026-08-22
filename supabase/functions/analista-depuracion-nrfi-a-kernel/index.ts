import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AGENT_ID = "@AnalistaDepuracionRNFI_A";
const VERSION = "ANALISTADEPURACIONRNFI-A-AGENT-1.2";
const KERNEL = "ANALISTADEPURACIONRNFI-A-KERNEL-1.2-CONTROL-PLANE";
const POLICY = "DEPURNRFI-A-POLICY-1.0";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ outcome:"REJECTED", reason:"POST_REQUIRED" }, { status:405 });
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return Response.json({ outcome:"REJECTED", reason:"RUNTIME_CONFIGURATION_MISSING" }, { status:500 });
  let b:any; try { b = await req.json(); } catch { return Response.json({ outcome:"REJECTED", reason:"INVALID_JSON" }, { status:400 }); }
  if (b?.agent_id != null && b.agent_id !== AGENT_ID) return Response.json({ outcome:"REJECTED", reason:"WRONG_AGENT_IDENTITY", expected:AGENT_ID }, { status:400 });
  const db = createClient(supabaseUrl, serviceKey, { auth:{ persistSession:false } });
  const action = String(b?.action ?? "");
  const map: Record<string,[string,(x:any)=>Record<string,unknown>]> = {
    start_run:["depurnrfi_a_start_run", x=>({p_slate_date:x.slate_date,p_policy_version:x.policy_version ?? POLICY,p_idempotency_key:x.idempotency_key,p_test_mode:!!x.test_mode,p_upstream_manifest_id:x.upstream_manifest_id ?? null,p_upstream_packet_hash:x.upstream_packet_hash ?? null,p_synthetic_fixture:x.synthetic_fixture ?? null})],
    status:["depurnrfi_a_status", x=>({p_run:x.run_id})],
    add_evidence:["depurnrfi_a_add_evidence", x=>({p_run:x.run_id,p_phase:x.phase_code,p_evidence_type:x.evidence_type,p_source_ref:x.source_ref,p_payload:x.payload ?? {},p_expected_state:x.expected_state_version})],
    record_requirement:["depurnrfi_a_record_requirement", x=>({p_run:x.run_id,p_requirement_id:x.requirement_id,p_status:x.status,p_execution_detail:x.execution_detail ?? {},p_evidence_ids:x.evidence_ids ?? [],p_expected_state:x.expected_state_version})],
    open_research_request:["depurnrfi_a_open_research_request", x=>({p_run:x.run_id,p_phase:x.phase_code,p_game_id:x.game_id ?? null,p_question:x.question,p_materiality:x.materiality,p_expected_state:x.expected_state_version})],
    resolve_research_request:["depurnrfi_a_resolve_research_request", x=>({p_run:x.run_id,p_request:x.request_id,p_evidence:x.evidence_id,p_expected_state:x.expected_state_version})],
    register_drive_readback:["depurnrfi_a_register_drive_readback", x=>({p_run:x.run_id,p_artifact_type:x.artifact_type ?? "FINAL_DIALOGUE_REPORT_A",p_document_id:x.document_id,p_document_url:x.document_url,p_content_sha256:x.content_sha256,p_metadata:x.metadata ?? {},p_expected_state:x.expected_state_version})],
    commit_phase:["depurnrfi_a_commit_phase", x=>({p_run:x.run_id,p_phase:x.phase_code,p_payload:x.payload ?? {},p_expected_state:x.expected_state_version})],
    receive_counterpart:["depurnrfi_a_receive_counterpart_report", x=>({p_run:x.run_id,p_payload:x.report_payload ?? {},p_declared_sha256:x.report_sha256,p_expected_state:x.expected_state_version})],
    register_user_authorization:["depurnrfi_a_register_user_authorization", x=>({p_run:x.run_id,p_user_message_hash:x.user_message_hash,p_source:x.source ?? "CHAT_USER_EXPLICIT",p_allowed_discrepancy_id:x.allowed_discrepancy_id ?? null,p_metadata:x.metadata ?? {},p_expected_state:x.expected_state_version})],
    add_dialogue_event:["depurnrfi_a_add_dialogue_event", x=>({p_run:x.run_id,p_discrepancy_id:x.discrepancy_id,p_turn_no:x.turn_no,p_actor:x.actor_agent_id,p_resolution:x.resolution,p_evidence_refs:x.evidence_refs ?? [],p_causal_argument:x.causal_argument,p_payload:{...(x.payload ?? {}),authorization_id:x.authorization_id ?? x?.payload?.authorization_id ?? null},p_expected_state:x.expected_state_version})],
    receive_d_closing:["depurnrfi_a_receive_d_closing", x=>({p_run:x.run_id,p_payload:x.report_payload ?? {},p_declared_sha256:x.report_sha256,p_expected_state:x.expected_state_version})],
    finalize_dialogue:["depurnrfi_a_finalize_dialogue", x=>({p_run:x.run_id,p_payload:x.payload ?? {},p_expected_state:x.expected_state_version})],
    prepare_downstream:["depurnrfi_a_prepare_downstream_handoff", x=>({p_run:x.run_id,p_expected_state:x.expected_state_version})],
    reopen:["depurnrfi_a_reopen_from_phase", x=>({p_run:x.run_id,p_phase:x.phase_code,p_reason_type:x.reason_type,p_reason_ref:x.reason_ref,p_expected_state:x.expected_state_version})]
  };
  const spec=map[action];
  if (!spec) return Response.json({ outcome:"REJECTED", reason:"UNKNOWN_ACTION", agent_id:AGENT_ID, version:VERSION, kernel:KERNEL }, { status:400 });
  const [rpc,args]=spec; const {data,error}=await db.rpc(rpc,args(b));
  if (error) return Response.json({ outcome:"REJECTED", reason:"KERNEL_RPC_ERROR", detail:error.message, agent_id:AGENT_ID, version:VERSION, kernel:KERNEL }, { status:400 });
  return Response.json({ outcome:"ACCEPTED", agent_id:AGENT_ID, version:VERSION, kernel:KERNEL, action, result:data });
});