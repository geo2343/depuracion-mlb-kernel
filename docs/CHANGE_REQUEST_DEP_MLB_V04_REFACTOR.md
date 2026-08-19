# CHANGE_REQUEST + REFACTOR_REVIEW — @DepuracionMLB — V0.4

Date: 2026-08-19
Target: `DEP-MLB-AGENT-1.2 / DEP-MLB-KERNEL-0.4-AUTONOMOUS-REFACTOR`
Drive review: `1Ch5auBTRgsGdhSQf8Uy8VQ9L_LfL82cZ3hBd6NV2PGY`

## 1. Error observed
- F6/F7/F8 were enforced universally, contradicting progressive depth and conditional F6.
- F10 did not physically require `CHAT_REPORT_COMPLETE`, `DELIVERY_STATUS` or the complete R1 handoff fields.
- Claims could technically carry an empty evidence array.
- Evidence snapshot/hash/origin/as_of were not fully bound to the originating tool event.
- Drive readback was not bound to a specific Google Drive tool event.
- Operational documents still contained superseded V0.1/V0.2 wording.
- Kernel 0.3 accumulated more than three material patches without the Constitution-mandated refactor review.

## 2. Root cause
0.3 was hardened incrementally around local failures. Coverage enforcement drifted into equal-depth enforcement and delivery/evidence controls were not consolidated against the complete V0.3 Constitution.

## 3. Existing control that should have covered it
Constitution V0.3: progressive depth, conditional F6, survivor-focused F7-F8, F10 Delivery QA / MLB_CHAT_REPORT_STANDARD R1, and section 24 anti-patch governance.

## 4. Why it failed
The refactor review was not activated after the third material patch and control-plane hardening was treated as incremental patching rather than a consolidated version change.

## 5. Minimum change
Promote 1.2/0.4 and consolidate enforcement: selective phase targeting, stronger evidence lineage/hashes, Drive readback→tool-event binding, typed handoff, persisted/validated R1 chat report, and F10 closure only when delivery QA is complete.

## 6. Rules merged/replaced
0.4 supersedes 0.3 operationally without deleting history. F2-F5 remain universal; F6 targets only DISCRIMINANT; F7-F8 target only SURVIVE; F9 maintains comparative closure and symmetric rescue; F10 integrates handoff + Drive + chat R1.

## 7. Owner
AI_AGENT owns sports semantics and causal judgment. Kernel owns identity, phase targeting/order, lineage, hashes, freeze, audit, coverage, delivery QA and closure. No metric-vote system is introduced.

## 8. False positive / negative effect
Selective depth reduces false negatives from over-investigating weak paths while F9 preserves rescue. Stronger handoff/evidence controls reduce false positives caused by thin or ungrounded outputs.

## 9. Cost / complexity
Adds phase-target derivation, candidate-schema validation, chat-report persistence and Drive-event binding, while removing redundant F6-F8 research on STOP games.

## 10. Ablation / comparison
0.4 must reject or correctly route: F6 on STOP; F7/F8 on eliminated games; empty claim evidence; mismatched snapshot hash/origin; Drive verification without Drive tool event; thin candidate payload; F10 without chat R1; manual close; phase skip; prior-run reuse.

## 11. Prospective validation
Run a controlled non-sports E2E 0.4 first. Then validate real sports execution quality in a future fresh autonomous MLB run. The controlled E2E does not certify sports quality.

**REFACTOR_REVIEW DECISION: APPROVED FOR IMPLEMENTATION.**
