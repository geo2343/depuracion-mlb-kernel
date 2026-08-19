# @DepuracionMLB — Exhaustive Selective Autonomous Agent

This repository contains the connected control plane for `@DepuracionMLB` / `@MLBdepuración`.

## Active authority

- Mother: **01 — CONSTITUCIÓN MAESTRA — @DepuracionMLB — V0.4**
- Drive ID: `1nod0j35fZeILy7fxUk5IPCT7_qn3f0sEFsxmLbDdfrA`
- Mother SHA-256: `0e7bcc838cb70f696c7a29950f304054ac9f7869fa0e166e6d2885bc2968fdc8`
- Agent: `DEP-MLB-AGENT-1.3`
- Kernel: `DEP-MLB-KERNEL-0.5-EXHAUSTIVE-SELECTIVE`
- Protocol: `DEPURACION_MLB_V0_4_EXHAUSTIVE_SELECTIVE`
- Real-money authority: `FALSE`

An alias invocation means execute the complete agent. A new execution requires a fresh invocation, fresh exclusive Drive folder/report, clean-room run, `AI_AGENT_ORCHESTRATOR` ownership and fresh same-run research.

## Core change from Kernel 0.4

Kernel 0.4 allowed progressive depth and up to four PRIMARY plus two POTENTIAL candidates. A real-run audit showed that this was too permissive and also exposed a temporal closure gap. Kernel 0.5 replaces that design.

### Exhaustive game burden

Every eligible game must complete all of F2 through F9:

- F2 starter representation;
- F3 offense representation;
- F4 dedicated bullpen/context representation;
- F5 structural cross;
- F6 mandatory deep verification;
- F7 full-game temporal viability;
- F8 materialization plus symmetric countercase;
- F9 Red Team, false-positive/false-negative review and horizontal comparison.

No game may be rejected by an early STOP before this burden is complete.

### Evidence burden

A database-derived packet audit cannot PASS unless the game has at least:

- 4 SPORTS_RESEARCH evidence rows;
- 4 source families;
- 2 source origins;
- dedicated `STARTER_PROFILE`, `OFFENSE_PROFILE`, `BULLPEN_CONTEXT`, `DEEP_VERIFICATION` evidence;
- all three causal claim types: `FAVORABLE_MECHANISM`, `ADVERSE_ROUTE`, `FULL_GAME_SYNTHESIS`;
- all 8 active F2-F9 artifacts.

`UNKNOWN != RISK` and also `UNKNOWN != SUPPORT`. A generic preview's failure to mention a bullpen problem is not affirmative bullpen evidence.

## Candidate policy

The final handoff may contain **at most two candidates total**.

- Candidate tier allowed: `PRIMARY_CANDIDATE`.
- `POTENTIAL_CANDIDATE` is disabled for new V0.5 executions.
- Zero, one or two candidates are valid.
- All remaining games finish `NOT_ADVANCED` with causal/comparative reasons.
- Empty slots are preferable to quota filling.

A PRIMARY candidate additionally requires:

- F8 `FULL_GAME_CHAIN_STATUS=COMPLETE`;
- at least two independent containment mechanisms;
- explicit governing failure route;
- F9 `CANDIDATE_GATE=PASS`;
- F9 `RED_TEAM_VERDICT=SURVIVES`;
- F9 `COMPARATIVE_VERDICT=TOP_TWO`.

The Kernel enforces representation and consistency; the AI remains the sports reasoner. There is no additive metric voting.

## Pregame temporal integrity

`EARLIEST_FIRST_PITCH` is the hard terminal deadline for the slate. F1-F10, game artifacts, F9 horizontal audit, packet freeze, database audits, Drive handoff and Chat R1 must all finish before that deadline. If the window is missed, the only valid terminal outcome is `DEPURATION_INCOMPLETE — NO HANDOFF`.

## Delivery

F10 requires 100% comparative closure, one frozen `EXHAUSTIVE` packet and `DATABASE_CONTROL_V05` audit PASS per game, verified RUN_DOSSIER, verified HANDOFF_REPORT, convergent frozen `MLB_CHAT_REPORT_STANDARD_R1`, no POTENTIAL candidates and at most two PRIMARY candidates. F10 PASS automatically closes the run and invocation.

## Validation

Controlled non-sports run: `TEST-DEP-AUTONOMOUS-E2E-V05`.

- F0-F10: 11/11 PASS.
- Controlled objects: 3.
- F2-F9 exhaustive coverage: 3/3.
- Database-derived packet audits: 3/3 PASS.
- Final controlled classification: 2 PRIMARY / 0 POTENTIAL / 1 NOT_ADVANCED.
- Handoff: PASS.
- Chat R1: PASS and frozen.
- Delivery: COMPLETE.
- Run/orchestration/invocation: automatically COMPLETED.

Adversarial controls physically confirmed: a weak third candidate was rejected, a POTENTIAL candidate in handoff was rejected, and a Pregame run whose earliest first pitch had already passed was rejected at F1.

The historical real run `DEP-MLB-20260819-REAL-1823-V04-A` is recorded as `POSTRUN_AUDIT_V05 = FAIL`, with `sports_certification_valid=false`, for `TEMPORAL_INTEGRITY_FAIL`, `CANDIDATE_OVERBREADTH`, and insufficient Full Game source depth in some games.

This controlled V0.5 validation contains no real MLB analysis. Real sports quality under Agent 1.3 must be evaluated in a future fresh clean-room invocation.

## Security

All `dep_mlb_*` tables have RLS enabled. There are zero `dep_mlb_*` functions without explicit `search_path` and zero SECURITY DEFINER functions. Run defaults are aligned to System V0.4 / Agent 1.3 / Kernel 0.5.

Vercel remains optional for standalone HTTP execution and is not part of connected ChatGPT process validation.
