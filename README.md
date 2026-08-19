# @DepuracionMLB — Connected Agent Runtime

This repository implements the connected control plane for `@DepuracionMLB`.

## Authority

Methodological authority remains the Google Drive document **01 — CONSTITUCIÓN MAESTRA — @DepuracionMLB — V0.3** (`1nod0j35fZeILy7fxUk5IPCT7_qn3f0sEFsxmLbDdfrA`). The large V0.1 document supplied on 2026-08-19 is explicitly historical/non-operative and is preserved only as reference.

## Current identity

- `AGENT_VERSION = DEP-MLB-AGENT-1.0`
- `SYSTEM_VERSION = DEP-MLB-V0.3`
- `KERNEL_VERSION = DEP-MLB-KERNEL-0.2-CONNECTED`
- `PROTOCOL_ID = DEPURACION_MLB_V0_3_PROGRESSIVE`
- `REAL_MONEY_AUTHORITY = FALSE`

## Architecture

The audited Python V0.1 runtime remains the regression baseline in Google Drive. V0.2 adds durable Supabase state, a physical agent registry, connector registry, run/game/tool/evidence/claim/packet/audit/handoff lineage, and versioned manifests.

`Web / MLB sources -> tool event -> evidence -> claim -> game packet -> freeze -> process audit -> Drive artifact -> horizontal audit -> handoff`

The LLM reasons. The Kernel enforces state, lineage, timestamps, freeze, coverage, caps and closure. Metrics are not votes.

## Scope

Only **MLB Full Game Under — Pregame depuration**. This agent filters and hands off. It does not authorize bets, open price/juice/EV/stake, or replace `@iainvestigadora`, `@ianalista`, `@iaindependiente` or JRC.

## Connector truth

- GitHub: versioned code and tests.
- Supabase: durable enforcement and registry.
- Google Drive: canonical authority and human-readable dossiers.
- Web: current research bridge when the agent runs inside ChatGPT.
- Vercel: optional standalone HTTP deployment; no project was visible through the connector at the 2026-08-19 verification, so deployment must not be claimed.

## Validation

The preserved V0.1 baseline was re-run on 2026-08-19: `70/70` pytest PASS, `500/500` randomized stress PASS, Python compile PASS. Those tests prove the control plane, not real sports quality. A controlled real MLB slate is still required before any claim of standalone production readiness.
