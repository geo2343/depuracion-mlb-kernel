import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AGENT_ID = "@InvestigadorGlobalFullUnder";
const VERSION = "INVESTIGADORGLOBALFULLUNDER-AGENT-1.2";
const KERNEL = "INVESTIGADORGLOBALFULLUNDER-KERNEL-1.2-MARKET-FIREWALL";
const MARKET_FIREWALL = "IGFU-MF-1.0";
const MAX_FETCH_BYTES = 2_000_000;

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
}
function decodeClaims(req: Request): Record<string, any> {
  const h = req.headers.get("authorization") ?? "";
  const token = h.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return {};
  try {
    const s = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = s + "=".repeat((4 - (s.length % 4)) % 4);
    return JSON.parse(atob(pad));
  } catch { return {}; }
}
function canMutate(req: Request) {
  const c = decodeClaims(req);
  return c.role === "service_role" || c.kendel_operator === true || c.app_metadata?.kendel_operator === true;
}
async function sha256Bytes(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}
function safeExternalUrl(raw: string) {
  let u: URL;
  try { u = new URL(raw); } catch { throw new Error("IGFU_SOURCE_URL_INVALID"); }
  if (u.protocol !== "https:") throw new Error("IGFU_HTTPS_SOURCE_REQUIRED");
  const h = u.hostname.toLowerCase();
  if (!h || h === "localhost" || h.endsWith(".local") || h.endsWith(".internal")) throw new Error("IGFU_PRIVATE_HOST_FORBIDDEN");
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(h) || h.includes(":")) throw new Error("IGFU_IP_LITERAL_FORBIDDEN");
  return u;
}
async function fetchOfficialSlate(date: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("IGFU_SLATE_DATE_INVALID");
  const url = `https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=${encodeURIComponent(date)}`;
  const res = await fetch(url, { headers: { "accept": "application/json", "user-agent": "Kendel-IGFU/1.2" } });
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (!res.ok) throw new Error(`IGFU_MLB_SCHEDULE_HTTP_${res.status}`);
  if (bytes.byteLength > MAX_FETCH_BYTES) throw new Error("IGFU_MLB_SCHEDULE_TOO_LARGE");
  const raw = new TextDecoder().decode(bytes);
  const data = JSON.parse(raw);
  const games: any[] = [];
  for (const d of (data.dates ?? [])) {
    for (const g of (d.games ?? [])) {
      const gamePk = String(g.gamePk ?? "");
      const away = String(g.teams?.away?.team?.name ?? "");
      const home = String(g.teams?.home?.team?.name ?? "");
      const start = String(g.gameDate ?? "");
      const stadium = String(g.venue?.name ?? "");
      if (!gamePk || !away || !home || !start || !stadium) throw new Error("IGFU_MLB_SCHEDULE_GAME_INCOMPLETE");
      games.push({ game_pk: gamePk, game_id: String(g.gameGuid ?? g.gamePk ?? ""), away_team: away, home_team: home, start_time: start, stadium, doubleheader_slot: g.doubleHeader === "Y" ? String(g.gameNumber ?? "") : null, metadata: { official_status: g.status?.detailedState ?? null, abstract_state: g.status?.abstractGameState ?? null, double_header: g.doubleHeader ?? null, game_number: g.gameNumber ?? null, scheduled_innings: g.scheduledInnings ?? null } });
    }
  }
  if (!games.length) throw new Error("IGFU_OFFICIAL_SLATE_EMPTY");
  return { url, raw, sha256: await sha256Bytes(bytes), games, retrieved_at: new Date().toISOString() };
}

Deno.serve(async (req: Request) => {
  if (req.method === "GET") return json(200, { ok:true, agent_id:AGENT_ID, agent_version:VERSION, kernel_version:KERNEL, authority:"RESEARCH_ONLY", phases:["F1","F2","F3","F4","F5","F6","F7","F8","F9"], has_f10:false, verified_fetch_only:true, official_slate_fetch:true, terminal_invalidation_supported:true, market_firewall:{version:MARKET_FIREWALL,market_data_in_sports_packet:false,market_reveal_authority:false,betting_line_allowed:false,odds_allowed:false} });
  if (req.method !== "POST") return json(405,{ok:false,error:"METHOD_NOT_ALLOWED"});
  let body: Record<string,any>; try { body=await req.json(); } catch { return json(400,{ok:false,error:"INVALID_JSON"}); }
  if (body.agent_id && body.agent_id !== AGENT_ID) return json(409,{ok:false,error:"AGENT_ID_MISMATCH"});
  const action=String(body.action ?? "");
  if (action !== "status" && !canMutate(req)) return json(403,{ok:false,error:"KERNEL_MUTATION_NOT_AUTHORIZED"});
  const url=Deno.env.get("SUPABASE_URL"), serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json(500,{ok:false,error:"KERNEL_ENV_MISSING"});
  const db=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  try {
    if (action === "status") { const {data,error}=await db.rpc("igfu_status",{p_run_id:body.run_id ?? null}); if(error)throw error; return json(200,{ok:true,action,agent_id:AGENT_ID,agent_version:VERSION,market_firewall_version:MARKET_FIREWALL,data}); }
    if (action === "start_run") {
      const slate=await fetchOfficialSlate(String(body.slate_date ?? ""));
      const {data:verificationId,error:ve}=await db.rpc("igfu_register_slate_verification",{p_slate_date:body.slate_date,p_source_url:slate.url,p_source_sha256:slate.sha256,p_normalized_games:slate.games,p_raw_metadata:{provider:"MLB_STATSAPI",bytes:slate.raw.length},p_retrieved_at:slate.retrieved_at,p_executor:"EDGE_VERIFIED_FETCH"}); if(ve)throw ve;
      const claims=decodeClaims(req);
      const {data:runId,error:re}=await db.rpc("igfu_start_run_verified",{p_slate_verification_id:verificationId,p_as_of:body.as_of ?? new Date().toISOString(),p_invocation_id:body.invocation_id ?? null,p_idempotency_key:body.idempotency_key,p_authorization_context:{gateway:"EDGE_V12_MF",market_firewall:MARKET_FIREWALL,claims:{role:claims.role ?? null,kendel_operator:claims.kendel_operator===true || claims.app_metadata?.kendel_operator===true}}}); if(re)throw re;
      return json(200,{ok:true,action,run_id:runId,slate_verification_id:verificationId,official_game_count:slate.games.length,official_slate_sha256:slate.sha256,market_data_included:false});
    }
    if (action === "fetch_source") {
      const u=safeExternalUrl(String(body.source_url ?? "")); const res=await fetch(u,{headers:{"accept":body.accept ?? "text/html,application/json,text/plain;q=0.9,*/*;q=0.1","user-agent":"Kendel-IGFU/1.2"},redirect:"follow"}); const bytes=new Uint8Array(await res.arrayBuffer()); if(bytes.byteLength>MAX_FETCH_BYTES)return json(413,{ok:false,error:"IGFU_SOURCE_RESPONSE_TOO_LARGE",bytes:bytes.byteLength}); const responseSha=await sha256Bytes(bytes); const ctype=res.headers.get("content-type") ?? "application/octet-stream"; let excerpt=""; if(/json|text|html|xml|javascript/i.test(ctype))excerpt=new TextDecoder().decode(bytes).slice(0,200_000);
      const {data,error}=await db.rpc("igfu_record_verified_fetch",{p_run_id:body.run_id,p_phase_code:body.phase_code,p_game_pk:body.game_pk ?? null,p_tool_name:"EDGE_HTTP_FETCH",p_source_url:u.toString(),p_request_payload:{method:"GET",requested_url:u.toString()},p_http_status:res.status,p_response_sha256:responseSha,p_content_type:ctype,p_response_excerpt:excerpt,p_as_of:body.as_of ?? new Date().toISOString(),p_metadata:{final_url:res.url,bytes:bytes.byteLength,redirected:res.redirected,market_firewall:MARKET_FIREWALL}}); if(error)throw error; return json(200,{ok:true,action,data,http_status:res.status,response_sha256:responseSha,content_type:ctype,bytes:bytes.byteLength,market_payload_may_not_enter_phase_artifacts:true});
    }
    const map: Record<string,{fn:string,args:Record<string,any>}>= {
      commit_phase:{fn:"igfu_commit_phase",args:{p_run_id:body.run_id,p_phase_code:body.phase_code,p_expected_state_version:body.expected_state_version,p_idempotency_key:body.idempotency_key,p_artifact:body.artifact}},
      invalidate_change:{fn:"igfu_invalidate_change",args:{p_run_id:body.run_id,p_object_class:body.object_class,p_game_pk:body.game_pk ?? null,p_reason:body.reason,p_evidence_id:body.evidence_id ?? null,p_expected_state_version:body.expected_state_version,p_idempotency_key:body.idempotency_key}},
      terminal_invalidate_run:{fn:"igfu_terminal_invalidate_run",args:{p_run_id:body.run_id,p_reason_code:body.reason_code,p_reason:body.reason,p_expected_state_version:body.expected_state_version,p_idempotency_key:body.idempotency_key}},
      authorize_chat_output:{fn:"igfu_authorize_chat_output",args:{p_run_id:body.run_id,p_phase_code:body.phase_code,p_output_kind:body.output_kind,p_content_sha256:body.content_sha256}},
      prepare_handoff:{fn:"igfu_prepare_handoff",args:{p_run_id:body.run_id,p_expected_state_version:body.expected_state_version,p_idempotency_key:body.idempotency_key}},
      mark_delivery:{fn:"igfu_mark_delivery",args:{p_run_id:body.run_id,p_consumer_agent_id:body.consumer_agent_id,p_packet_sha256:body.packet_sha256,p_receipt:body.receipt ?? {}}}
    };
    const op=map[action]; if(!op)return json(403,{ok:false,error:"ACTION_NOT_ALLOWED",action}); const {data,error}=await db.rpc(op.fn,op.args); if(error)throw error; return json(200,{ok:true,action,agent_id:AGENT_ID,agent_version:VERSION,market_firewall_version:MARKET_FIREWALL,data});
  } catch(e) { const message=e instanceof Error ? e.message : String(e); return json(409,{ok:false,action,error:message}); }
});
