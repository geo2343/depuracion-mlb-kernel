# AUDITORÍA INTEGRAL — @DepuracionMLB — Agent 1.2 / Kernel 0.4

Date: 2026-08-19
Mother methodology: V0.3
Active Mother plain-text SHA-256: `0e4b1382597930cc48b1f40a39d824a4f45208f505c462e9e623e31a0f8130d2`
Refactor review Drive ID: `1Ch5auBTRgsGdhSQf8Uy8VQ9L_LfL82cZ3hBd6NV2PGY`
Controlled E2E: `TEST-DEP-AUTONOMOUS-E2E-V04` (SPORTS_ANALYSIS=FALSE)

## Findings found and closed

1. Kernel 0.3 required F6/F7/F8 for all games, contradicting Mother progressive depth. Closed: F6 only DISCRIMINANT; F7/F8 only survivors; F9 returns to all games.
2. F10 did not physically require full DELIVERY_QA / CHAT R1. Closed: RUN_DOSSIER + HANDOFF_REPORT + typed handoff + frozen CHAT R1 + COMPLETE delivery required.
3. Drive verification trusted caller flags too much. Closed: every verified Drive artifact must bind to a specific Google Drive tool event carrying matching file ID/content hash.
4. Evidence lineage did not fully bind source/hash to tool response. Closed: DB derives snapshot hash and tool-response hash; sports research requires fresh Web event + URL/origin/as_of/family.
5. Incremental 0.3 hardening exceeded Mother anti-patch threshold. Closed: formal CHANGE_REQUEST + REFACTOR_REVIEW before 0.4.
6. Handoff duplicate-candidate check had a PL/pgSQL `gid` ambiguity. Found by E2E; migration fixed it before activation.
7. Completed run could accept new tool-event INSERTs. Closed: terminal trace sealed; post-F9 Web research requires new clean-room run.
8. Existing Drive mandate/status documents still described 0.3/0.2 as active. Closed: renamed and prepended V0.4 precedence notices; older content preserved as history only.
9. GitHub lacked a Kernel 0.4 migration source record while Supabase had the applied migrations. Closed with `supabase/013_kernel_04_autonomous_refactor.sql` plus this audit record.

## Controlled validation

Supabase registry contains 17/17 PASS tests for `DEP-MLB-KERNEL-0.4-AUTONOMOUS-REFACTOR`:
- F6 rejects F5 STOP.
- F7/F8 reject non-survivors.
- STOP path audit expected/observed artifacts = 5/5.
- DISCRIMINANT→SURVIVE expected/observed = 8/8.
- Evidence hash/origin derivation from tool lineage.
- Drive readback without linked event rejected.
- Handoff without CHAT R1 rejected.
- Caller audit values replaced by DATABASE_CONTROL_V04.
- F10 delivery QA requires Drive + Chat COMPLETE.
- F10 automatic run/invocation close.
- Completed-run metadata tamper rejected.
- Completed-run new tool event rejected.
- PASS handoff tamper rejected.
- Post-PASS phase artifact rejected.
- Pre-F9 material lineup change reopens F3+ only and supersedes old downstream artifacts.
- Post-F9 reopen rejected and requires new run.
- Complete controlled F0→F10 E2E PASS.

Controlled E2E terminal state:
- phase states PASS = 11/11 (F0-F10)
- packet process audits PASS = 2/2
- chat R1 QA = PASS
- delivery = COMPLETE
- run = COMPLETED
- orchestration = COMPLETED
- invocation = COMPLETED

This validates the autonomous orchestration and Kernel process only. It does not certify real sports judgment quality because the test deliberately used synthetic controlled objects.

## Security verification

- RLS enabled on every `dep_mlb_*` table.
- zero `dep_mlb_*` functions missing an explicit `search_path`.
- zero `dep_mlb_*` SECURITY DEFINER functions.
- Vercel is optional and remains NOT_VISIBLE; no standalone deployment claim is made.

## Authority separation

AI_AGENT owns sports semantic/causal judgment. Kernel owns process enforcement only. There is no additive metric voting and no betting authority. `REAL_MONEY_AUTHORITY = FALSE`.
