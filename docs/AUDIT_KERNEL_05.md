# @DepuracionMLB — Kernel 0.5 audit

Date: 2026-08-19

## Reason for refactor

Real run `DEP-MLB-20260819-REAL-1823-V04-A` exposed three material problems:

1. Candidate overbreadth: 4 PRIMARY + 2 POTENTIAL were allowed.
2. Temporal integrity: F9/packet/F10 work crossed first pitch for part of the slate.
3. Some Full Game statements relied too heavily on one generic preview.

The run is retained as history with `POSTRUN_AUDIT_V05=FAIL` and `sports_certification_valid=false`.

## New identity

- System: `DEP-MLB-V0.4`
- Agent: `DEP-MLB-AGENT-1.3`
- Kernel: `DEP-MLB-KERNEL-0.5-EXHAUSTIVE-SELECTIVE`
- Protocol: `DEPURACION_MLB_V0_4_EXHAUSTIVE_SELECTIVE`
- Mother SHA-256: `0e7bcc838cb70f696c7a29950f304054ac9f7869fa0e166e6d2885bc2968fdc8`

## Corrective controls

- F2-F9 mandatory for every eligible game.
- No early STOP.
- Dedicated starter, offense, bullpen/context and deep-verification evidence.
- Audit minimum: 4 sports evidence rows, 4 families, 2 origins, 3 causal claim types, 8 F2-F9 artifacts.
- `UNKNOWN != SUPPORT`.
- Maximum 2 candidates total.
- Only `PRIMARY_CANDIDATE`; POTENTIAL disabled.
- Candidate admission requires complete Full Game chain, at least two independent containment mechanisms, explicit governing failure route, Red Team survival and TOP_TWO comparison.
- Earliest first pitch is the hard terminal deadline for the entire Pregame run.

## Controlled E2E

Run: `TEST-DEP-AUTONOMOUS-E2E-V05`

- Sports analysis: FALSE.
- F0-F10: 11/11 PASS.
- Controlled objects: 3.
- Exhaustive F2-F9: 3/3.
- Database audits: 3/3 PASS via `DATABASE_CONTROL_V05`.
- Final classification: 2 PRIMARY / 0 POTENTIAL / 1 NOT_ADVANCED.
- Handoff: PASS.
- Chat R1: PASS and frozen.
- Delivery: COMPLETE.
- Run/orchestration/invocation: COMPLETED automatically.

## Adversarial tests

- Weak third candidate promotion blocked: `DEP_MLB_V05_CANDIDATE_REQUIRES_TWO_INDEPENDENT_MECHANISMS`.
- POTENTIAL in final handoff blocked: `DEP_MLB_V05_MAX_TWO_PRIMARY_NO_POTENTIAL`.
- Pregame execution after earliest first pitch blocked: `DEP_MLB_V05_F1_AFTER_EARLIEST_FIRST_PITCH_FORBIDDEN`.
- A shared immutability regression exposed by the temporal test was corrected with table-dispatched claim logic; the temporal test was rerun and passed.

## Security

- `dep_mlb_*` tables without RLS: 0.
- `dep_mlb_*` functions without explicit search_path: 0.
- SECURITY DEFINER functions: 0.
- Run defaults aligned to System V0.4 / Agent 1.3 / Kernel 0.5.

## Validation boundary

This validates autonomous process/enforcement only. It is not sports-performance validation. The first real Agent 1.3 run must be a new clean-room invocation and may not reuse V0.4 candidates or reasoning.
