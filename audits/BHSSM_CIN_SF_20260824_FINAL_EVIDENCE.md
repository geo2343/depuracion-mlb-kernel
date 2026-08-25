# BHSSM CIN @ SF — FINAL EXECUTION EVIDENCE

## Identidad de la corrida soberana de auditoría

- GitHub Actions run: `32792435359` (run #6)
- Job: `97636558784`
- Head commit ejecutado: `f4cf532583c18d974aa9d4d938117f34fdfd7c6e`
- Source snapshot: `dc36be0d29c98f75a80889e413cdf8ce405ad05b`
- Source snapshot timestamp: `2026-08-24T23:27:04Z`
- Historical event cutoff: `2026-08-23`
- First-pitch firewall: `2026-08-25T01:45:00Z`
- Artifact ID: `9543665073`
- Artifact ZIP SHA-256: `3ba3845bc72ee79d5d737d3633f63f7d74df942cfdf1ef6316bd982078477ec8`
- Artifact size: `1,854,428 bytes`
- Files uploaded: `23`

## Workflow result

All operational steps completed successfully:

1. Checkout kernel — SUCCESS
2. Python environment — SUCCESS
3. Statistical dependencies — SUCCESS
4. Sovereign source snapshot fetch — SUCCESS
5. BHSSM CIN-SF numeric execution — SUCCESS
6. Strict BHSSM certification gate — SUCCESS
7. Auditable artifact upload — SUCCESS

Operational workflow success must not be confused with statistical certification.

## Numeric execution before certification gate

- League pitch rows before cutoff: `583,853`
- Target pitch rows: `18,948`
- Target swing rows: `8,624`
- Target PA rows: `4,674`
- Target BIP rows: `3,124`
- Technical-state checkpoints: `448`
- Change-point candidates computed: `4`
- Historical-version candidate rows computed: `18`
- Temporal-pattern candidates computed: `4`

Temporal validation:

- TP: `1`
- FP: `1`
- FN: `7`
- Precision: `0.50`
- Recall: `0.125`
- F1: `0.20`
- Detection delay: `1 checkpoint`

## Strict certification gate result

`MODEL_CERTIFICATION_GATE = FAIL`

Certification gaps recorded by the executed gate:

1. TEMPORAL_OUT_OF_SAMPLE_TEST
2. MISSING_DATA_TEST
3. FALSE_NEGATIVE_TEST
4. REGIME_CHANGE_PERTURBATION_TEST
5. PITCH_RECLASSIFICATION_ROBUSTNESS_TEST
6. THRESHOLD_PRECOMMITMENT_TEST
7. CONTEXT_MODEL_CONVERGENCE_TEST
8. CONTEXT_COVARIATE_COMPLETENESS_TEST
9. HIERARCHICAL_METRIC_MODEL_COMPLIANCE_TEST
10. LATENT_STATE_POSTERIOR_MODEL_TEST
11. STATE_UNCERTAINTY_CALIBRATION_TEST
12. VERSION_DURATION_MODEL_COMPLIANCE_TEST
13. HEALTH_ROLE_COUNTEREVIDENCE_TEST
14. SWING_MECHANICS_ATOMIC_TEST
15. BIP_EXPECTED_CONVERSION_ATOMIC_TEST
16. LINEUP_STATE_HISTORY_COVERAGE_TEST
17. PATTERN_DEPENDENCE_AWARE_VALIDATION_TEST

## Coverage exception list

Players with fewer than three technical-state checkpoints and therefore ineligible for the implemented change detector:

- Ivan Johnson — CIN — 0 checkpoints
- Turner Hill — SF — 0 checkpoints
- Nate Furman — SF — 0 checkpoints
- Shay Whitcomb — SF — 1 checkpoint

## Authoritative versus diagnostic outputs

The final artifact was inspected after download. The strict gate produced the required separation:

- `CHANGE_POINT_REGISTRY.csv`: **0 authorized rows**
- `HISTORICAL_VERSION_MAP.csv`: **0 authorized rows**
- `PATTERN_REGISTRY.csv`: **0 authorized rows**

Diagnostic evidence was preserved separately:

- `CHANGE_POINT_CANDIDATES_UNCERTIFIED.csv`: **4 rows**
- `HISTORICAL_VERSION_CANDIDATES_UNCERTIFIED.csv`: **18 rows**
- `PATTERN_CANDIDATES_UNCERTIFIED.csv`: **4 rows**
- `AS_OF_FILTERED_HISTORY_UNCERTIFIED.csv`: preserved for audit

## Final sovereign status

- `BHSSM_STATISTICAL_AUDIT = FAIL`
- `BHSSM_EXECUTION_STATUS = BLOCKED_BY_MODEL_CERTIFICATION`
- `AS_OF_FILTERED_HISTORY_STATUS = COMPUTED_NOT_CERTIFIED_FOR_CVD`
- `CHANGE_POINT_REGISTRY_STATUS = NOT_AUTHORIZED`
- `HISTORICAL_VERSION_MAP_STATUS = NOT_AUTHORIZED`
- `PATTERN_REGISTRY_STATUS = NOT_AUTHORIZED`
- `HANDOFF_TO_CVD = BLOCKED`
- `CURRENT_VERSION = NOT AUTHORIZED / OUTSIDE BHSSM AUTHORITY`
- `TODAY_STATE = NOT AUTHORIZED / OUTSIDE BHSSM AUTHORITY`
- `P(HIT) = NOT AUTHORIZED`
- `BETTING_DECISION = NOT AUTHORIZED`

This is a fail-closed result. No candidate was promoted merely to produce a complete-looking answer.
