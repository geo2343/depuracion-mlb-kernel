# @DepuracionMLB — Autonomous Connected Agent

This repository contains the connected autonomous control plane for `@DepuracionMLB` / `@MLBdepuración`.

## Authority

Methodological authority is the Google Drive document **01 — CONSTITUCIÓN MAESTRA — @DepuracionMLB — V0.3** (`1nod0j35fZeILy7fxUk5IPCT7_qn3f0sEFsxmLbDdfrA`). Current plain-text SHA-256 after the Autonomous Agent Orchestration Notice is:

`a707f5a44ad83d686e608a2c63d5dfbd5bad6f94e7e250b677143b169c8c844f`

The historical V0.1 material is non-operative. Prior-run sports conclusions are audit/history only and cannot seed a new run.

## Current identity

- `AGENT_VERSION = DEP-MLB-AGENT-1.1`
- `SYSTEM_VERSION = DEP-MLB-V0.3`
- `KERNEL_VERSION = DEP-MLB-KERNEL-0.3-AUTONOMOUS`
- `PROTOCOL_ID = DEPURACION_MLB_V0_3_PROGRESSIVE`
- `EXECUTION_MODEL = ALIAS_BOUND_AUTONOMOUS_AGENT`
- `REAL_MONEY_AUTHORITY = FALSE`

## What invocation means

An invocation of `@DepuracionMLB`, `@MLBdepuración` or `@MLBdepuracion` means **execute the complete agent**, not describe it and not manually imitate its analysis outside the agent state machine.

Required start chain:

`alias -> new Drive folder/report -> Drive existence receipt -> dep_mlb_agent_invocations -> new run owned by AI_AGENT_ORCHESTRATOR -> F0..F10`

A new autonomous run is physically rejected if it lacks the invocation record, uses a manual owner, reuses an older Drive report, lacks verification that the new report exists, or disables clean room.

## Agent vs Kernel

The **AI_AGENT** owns sports intelligence: semantic relevance, mechanisms, causal materialization, countercases, false-positive/false-negative reasoning and comparative judgment.

The **Kernel** owns enforcement only: invocation identity, run isolation, phase order, tool-event/evidence lineage, required phase artifacts, timestamps, hashes, freezes, coverage, audits, Drive readback and terminal closure.

Metrics are not votes and the Kernel does not make the sports pick.

## Physical phase machine

- F0: invocation + clean-room binding
- F1: universe/identity/snapshot
- F2: starter screen
- F3: offense screen
- F4: bullpen/context
- F5: structural cross
- F6: discriminant resolution
- F7: full-game viability
- F8: materialization + symmetric countercase
- F9: Red Team + false-negative rescue + horizontal audit
- F10: shortlist + handoff validation

F2-F9 cannot PASS from prose alone. The AI must persist the exact phase-specific semantic artifact for every eligible game. The Kernel checks presence, required semantic fields, evidence lineage, non-thin reasoning and hash integrity; it does not decide whether the sports conclusion is favorable or adverse.

F10 PASS requires one frozen audited packet per eligible game plus a verified Drive handoff. F10 PASS automatically closes the run and invocation. Manual `COMPLETED` before F10 is rejected.

## Database-derived audit

For Agent 1.1 / Kernel 0.3, `dep_mlb_process_audits.audit_status` is derived by `DATABASE_CONTROL`. Caller-supplied PASS/FAIL has no authority. The database recomputes the audit from tool events, evidence, claims, required F2-F9 game artifacts, F0-F9 phase PASS state, packet freeze/hash and verified Drive readback, then synchronizes the result to the packet.

## Fresh evidence rule

For Agent 1.1 / Kernel 0.3, `SPORTS_RESEARCH` evidence must originate from a **fresh Web tool event created after the run started**. A Drive document or historical run cannot be inserted as sports evidence.

## Connectors

- Web: required for fresh current sports research.
- Google Drive: required for authority, new-run dossier creation/readback and final handoff.
- Supabase: required for invocation binding, phase machine, lineage, audit and closure.
- GitHub: required for versioned manifests, protocols, runtime contracts and migrations.
- Vercel: optional for standalone HTTP deployment; it is not required for ChatGPT-connected agent execution and must not be claimed deployed until physically visible.

## Validation status

The former run `DEP-MLB-20260820-REAL-1557A` was reclassified `AUDIT_ONLY` because it was manually executed by the assistant under Agent 1.0 / Kernel 0.2. It does **not** certify the autonomous Agent 1.1 / Kernel 0.3.

Kernel 0.3 has 15 controlled tests persisted in Supabase. The controlled autonomous run `TEST-DEP-AUTONOMOUS-E2E-V03` completed F0→F10, produced phase artifacts, froze a packet, received a database-derived process audit PASS, validated a Drive-backed handoff and automatically closed both the run and invocation. Its Drive audit receipt is `17PhvlEpDySVTtlPFo9ANAJJkEWjT0K0TePtBRQAINVY` with SHA-256 `ec14ed8d10e876d8aebf753a3cec9edb2385b3d58fda7d6a3b7b81c0efe0a78b`.

Therefore **autonomous orchestrator / Kernel process validation = PASS**. This controlled run was explicitly not sports analysis. **Real sports execution quality under Agent 1.1 / Kernel 0.3 has not yet been performed**, and must be validated separately by a future fresh agent invocation.
