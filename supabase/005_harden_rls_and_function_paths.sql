alter table public.dep_mlb_runs enable row level security;
alter table public.dep_mlb_games enable row level security;
alter table public.dep_mlb_tool_events enable row level security;
alter table public.dep_mlb_evidence enable row level security;
alter table public.dep_mlb_claims enable row level security;
alter table public.dep_mlb_game_packets enable row level security;
alter table public.dep_mlb_process_audits enable row level security;
alter table public.dep_mlb_handoffs enable row level security;
alter table public.dep_mlb_connector_registry enable row level security;
alter table public.dep_mlb_drive_artifacts enable row level security;

alter function public.dep_mlb_validate_tool_event_game() set search_path = public, pg_temp;
alter function public.dep_mlb_validate_evidence_lineage() set search_path = public, pg_temp;
alter function public.dep_mlb_validate_claim_evidence() set search_path = public, pg_temp;
alter function public.dep_mlb_guard_packet_freeze() set search_path = public, pg_temp;
alter function public.dep_mlb_sync_packet_audit() set search_path = public, pg_temp;
alter function public.dep_mlb_validate_handoff() set search_path = public, pg_temp;
alter function public.dep_mlb_guard_drive_artifact_verification() set search_path = public, pg_temp;

update public.agent_registry set metadata = metadata || jsonb_build_object('dep_mlb_rls_enabled',true,'dep_mlb_function_search_path_hardened',true), updated_at=now() where agent_id='@DepuracionMLB';
