import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AGENT_ID = "@AnalistaDepuracionFullUnder_A";
const VERSION = "ANALISTADEPURACIONFULLUNDER-A-AGENT-1.2";
const SYSTEM_VERSION = "ANALISTADEPURACIONFULLUNDER-A-SYSTEM-1.2";
const KERNEL = "ANALISTADEPURACIONFULLUNDER-A-KERNEL-1.2-CONTROL-PLANE";
const PROTOCOL = "FULLUNDER_GLOBAL_DEPURATION_A_DIALOGUE_V1_1";
const POLICY = "FUDA-POLICY-1.1";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ outcome: "REJECTED", reason: "POST_REQUIRED" }, { status: 405 });
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return Response.json({ outcome: "REJECTED", reason: "RUNTIME_CONFIGURATION_MISSING" }, { status: 500 });
  const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  let body: any;
  try { body = await req.json(); } catch { return Response.json({ outcome: "REJECTED", reason: "INVALID_JSON" }, { status: 400 }); }
  if (body?.agent_id != null && body.agent_id !== AGENT_ID) return Response.json({ outcome:"REJECTED", reason:"WRONG_AGENT_IDENTITY", expected:AGENT_ID }, { status:400 });
  const action = String(body?.action ?? "");
  const map: Record<string, [string, (b:any)=>Record<string,unknown>]> = {
    start_run: ["fuda_start_run_v11", b => ({ p_agent_id: b.agent_id, p_upstream_manifest_id: b.upstream_manifest_id, p_policy_version: b.policy_version ?? POLICY, p_idempotency_key: b.idempotency_key, p_test_mode: !!b.test_mode })],
    status: ["fuda_status", b => ({ p_run: b.run_id })],
    add_evidence: ["fuda_add_evidence_ref", b => ({ p_run:b.run_id,p_requirement:b.requirement_id,p_phase:b.phase_id,p_source_type:b.source_type,p_source_id:b.source_id,p_source_sha:b.source_sha256 ?? null,p_upstream_artifact:b.upstream_artifact_id ?? null,p_as_of:b.as_of ?? null,p_payload:b.evidence_payload ?? {},p_expected_state:b.expected_state_version })],
    record_requirement: ["fuda_record_requirement", b => ({ p_run:b.run_id,p_requirement:b.requirement_id,p_status:b.status,p_execution_summary:b.execution_summary,p_observed:b.observed_result ?? {},p_physical_proof:b.physical_proof ?? {},p_expected_state:b.expected_state_version })],
    open_research_request: ["fuda_open_research_request", b => ({ p_run:b.run_id,p_game_pk:b.game_pk ?? null,p_missing_fact:b.missing_fact,p_why:b.why_material,p_question:b.exact_question,p_changes:b.what_changes_if_resolved,p_expected_state:b.expected_state_version })],
    resolve_research_request: ["fuda_resolve_research_request", b => ({ p_request:b.request_id,p_evidence_ref:b.evidence_ref_id,p_expected_state:b.expected_state_version })],
    commit_phase: ["fuda_commit_phase_v11", b => ({ p_run:b.run_id,p_phase:b.phase_id,p_expected_state:b.expected_state_version,p_artifact_type:b.artifact_type,p_artifact_payload:b.artifact_payload ?? {},p_idempotency_key:b.idempotency_key })],
    reopen_from_phase: ["fuda_reopen_from_phase_v11", b => ({ p_run:b.run_id,p_target_phase:b.target_phase,p_reason_type:b.reason_type,p_reason_ref:b.reason_ref,p_expected_state:b.expected_state_version })],
    receive_counterpart: ["fuda_receive_counterpart_report", b => ({ p_run:b.run_id,p_producer:b.producer_agent_id,p_report_type:b.report_type,p_report_sha:b.report_sha256,p_payload:b.report_payload ?? {},p_expected_state:b.expected_state_version })],
    authorize_dialogue: ["fuda_authorize_dialogue", b => ({ p_run:b.run_id,p_approved_by:b.approved_by,p_payload:b.approval_payload ?? {},p_expected_state:b.expected_state_version })],
    receive_d_closing: ["fuda_receive_d_closing_v11", b => ({ p_run:b.run_id,p_producer:b.producer_agent_id,p_sha:b.report_sha256,p_payload:b.report_payload ?? {},p_expected_state:b.expected_state_version })],
    prepare_downstream: ["fuda_prepare_downstream_handoff_v11", b => ({ p_run:b.run_id,p_expected_state:b.expected_state_version,p_idempotency_key:b.idempotency_key })],
  };
  const spec = map[action];
  if (!spec) return Response.json({ outcome:"REJECTED", reason:"UNKNOWN_ACTION", agent_id:AGENT_ID, version:VERSION, system_version:SYSTEM_VERSION, kernel:KERNEL, protocol:PROTOCOL }, { status:400 });
  const [rpc, argsFn] = spec;
  const { data, error } = await db.rpc(rpc, argsFn(body));
  if (error) return Response.json({ outcome:"REJECTED", reason:"KERNEL_RPC_ERROR", detail:error.message, agent_id:AGENT_ID, version:VERSION, system_version:SYSTEM_VERSION, kernel:KERNEL, protocol:PROTOCOL }, { status:400 });
  return Response.json({ outcome:"ACCEPTED", agent_id:AGENT_ID, version:VERSION, system_version:SYSTEM_VERSION, kernel:KERNEL, protocol:PROTOCOL, action, result:data });
});