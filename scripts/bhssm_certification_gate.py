#!/usr/bin/env python3
"""Strict post-execution certification gate for BHSSM.

Separates computed diagnostics from outputs the BHSSM contract may certify.
The gate fails closed: successful code execution is not model certification.
If a required statistical, data, governance, or implementation control is not
PASS, change points, historical versions and temporal patterns remain diagnostic
only; CVD handoff and every downstream current-version/probability claim are blocked.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import pandas as pd

OUT = Path(os.environ.get("BHSSM_OUTPUT_DIR", "bhssm_outputs/CIN_SF_2026-08-24"))
AUDIT_PATH = OUT / "BHSSM_AUDIT.json"
CONFIG_PATH = OUT / "BHSSM_ENGINE_CONFIG.json"
CP_PATH = OUT / "CHANGE_POINT_REGISTRY.csv"
VM_PATH = OUT / "HISTORICAL_VERSION_MAP.csv"
PATTERN_PATH = OUT / "PATTERN_REGISTRY.csv"
HISTORY_PATH = OUT / "AS_OF_FILTERED_HISTORY.csv"
MANIFEST_PATH = OUT / "SOURCE_MANIFEST.json"
REPORT_PATH = OUT / "REPORT.md"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(obj, path: Path):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")


def preserve_candidates(path: Path, candidate_name: str, empty_authoritative: bool = True):
    if not path.exists():
        return 0
    df = pd.read_csv(path)
    df.to_csv(OUT / candidate_name, index=False)
    if empty_authoritative:
        pd.DataFrame(columns=df.columns).to_csv(path, index=False)
    return len(df)


def history_coverage():
    history = pd.read_csv(HISTORY_PATH) if HISTORY_PATH.exists() else pd.DataFrame()
    manifest = load_json(MANIFEST_PATH) if MANIFEST_PATH.exists() else {"target_batters": []}
    rows = []
    for p in manifest.get("target_batters", []):
        bid = int(p["id"])
        h = history[history["batter_id"].eq(bid)] if not history.empty else pd.DataFrame()
        checkpoints = int(len(h))
        rows.append({
            "batter_id": bid,
            "batter": p["name"],
            "team": p["team"],
            "technical_state_checkpoints": checkpoints,
            "change_detection_eligible": checkpoints >= 3,
            "latest_as_of": None if h.empty else str(h["as_of"].max()),
            "minimum_sample_authority": None if h.empty else float(h["sample_authority"].min()),
            "median_sample_authority": None if h.empty else float(h["sample_authority"].median()),
        })
    insufficient = [r for r in rows if not r["change_detection_eligible"]]
    obj = {
        "target_batters": len(rows),
        "change_detection_eligible_batters": len(rows) - len(insufficient),
        "insufficient_history_batters": insufficient,
        "players": rows,
    }
    dump_json(obj, OUT / "LINEUP_STATE_HISTORY_COVERAGE.json")
    return obj


def main():
    audit = load_json(AUDIT_PATH)
    config = load_json(CONFIG_PATH)
    tests = dict(audit.get("tests", {}))
    coverage = history_coverage()

    # Controls with direct evidence from the executed run.
    required = {
        "TEMPORAL_OUT_OF_SAMPLE_TEST": tests.get("TEMPORAL_OUT_OF_SAMPLE_TEST", "MISSING"),
        "NO_LEAKAGE_TEST": tests.get("NO_FUTURE_DATA", "MISSING"),
        "MISSING_DATA_TEST": tests.get("MISSING_DATA_TEST", "MISSING"),
        "FALSE_POSITIVE_TEST": tests.get("FALSE_POSITIVE_TEST", "MISSING"),
        "FALSE_NEGATIVE_TEST": tests.get("FALSE_NEGATIVE_TEST", "MISSING"),
        "REPRODUCIBILITY_TEST": tests.get("REPRODUCIBILITY_TEST", "MISSING"),
    }

    # The initial runner over-labelled several controls. These are downgraded
    # because inspection of the implementation shows that the named contractual
    # test was not actually executed in full.
    required["REGIME_CHANGE_PERTURBATION_TEST"] = "LIMITED"
    required["PITCH_RECLASSIFICATION_ROBUSTNESS_TEST"] = "LIMITED"

    # The game-specific thresholds were selected inside the CIN@SF execution.
    # Freezing after selection is reproducibility, not precommitment.
    required["THRESHOLD_PRECOMMITMENT_TEST"] = "FAIL"

    # Execution logs emitted LogisticRegression ConvergenceWarning messages.
    required["CONTEXT_MODEL_CONVERGENCE_TEST"] = "LIMITED"

    # The context model implements pitch family, velocity/movement/location,
    # pitcher hand, count and a prior pitcher-quality proxy, but does not fully
    # implement every relevant optional/competitive context specified by the
    # contract (park/game state, starter-reliever, catcher, defense when relevant).
    required["CONTEXT_COVARIATE_COMPLETENESS_TEST"] = "LIMITED"

    # The implemented state construction uses rolling residual averages and
    # standardized composite states. It does not yet realize the complete
    # hierarchical Beta/Logistic-Binomial and robust Student-t posterior layer
    # contemplated by the BHSSM statistical contract.
    required["HIERARCHICAL_METRIC_MODEL_COMPLIANCE_TEST"] = "LIMITED"
    required["LATENT_STATE_POSTERIOR_MODEL_TEST"] = "LIMITED"
    required["STATE_UNCERTAINTY_CALIBRATION_TEST"] = "LIMITED"

    # The version duration gate enforces minimum checkpoints but is explicitly
    # a semi-Markov-like rule, not a fully fitted semi-Markov duration model.
    required["VERSION_DURATION_MODEL_COMPLIANCE_TEST"] = "LIMITED"

    # Exposure-shift counterevidence is tested, but injury/IL, playing-time,
    # platoon and lineup-role competitor hypotheses are not ingested here.
    required["HEALTH_ROLE_COUNTEREVIDENCE_TEST"] = "LIMITED"

    # Swing-mechanics atomic fields and deep expected BIP conversion are absent
    # from the frozen source at the authority required by the contract.
    required["SWING_MECHANICS_ATOMIC_TEST"] = tests.get("SWING_MECHANICS_ATOMIC", "MISSING")
    required["BIP_EXPECTED_CONVERSION_ATOMIC_TEST"] = tests.get("BIP_EXPECTED_CONVERSION_ATOMIC", "MISSING")

    required["LINEUP_STATE_HISTORY_COVERAGE_TEST"] = (
        "PASS" if not coverage["insufficient_history_batters"] else "LIMITED"
    )

    # Pattern discovery pools overlapping rolling checkpoints/repeated measures.
    # FDR correction over four p-values does not by itself solve within-player
    # dependence; dependence-aware temporal validation is still required.
    required["PATTERN_DEPENDENCE_AWARE_VALIDATION_TEST"] = "LIMITED"

    failures = [k for k, v in required.items() if v != "PASS"]
    gate = "PASS" if not failures else "FAIL"

    cp_count = preserve_candidates(CP_PATH, "CHANGE_POINT_CANDIDATES_UNCERTIFIED.csv")
    version_count = preserve_candidates(VM_PATH, "HISTORICAL_VERSION_CANDIDATES_UNCERTIFIED.csv")
    pattern_count = preserve_candidates(PATTERN_PATH, "PATTERN_CANDIDATES_UNCERTIFIED.csv")
    history_count = preserve_candidates(
        HISTORY_PATH, "AS_OF_FILTERED_HISTORY_UNCERTIFIED.csv", empty_authoritative=False
    )

    audit["initial_runner_audit_label"] = audit.get("BHSSM_STATISTICAL_AUDIT")
    audit["initial_runner_execution_label"] = audit.get("BHSSM_EXECUTION_STATUS")
    audit["initial_pass_labels_overridden_by_external_code_audit"] = [
        "REGIME_CHANGE_TEST",
        "PITCH_RECLASSIFICATION_TEST",
        "COUNTEREVIDENCE_SEARCHED",
        "VERSION_DURATION_CONTROLLED",
        "CONTEXT_MODEL_APPLIED",
    ]
    audit["certification_tests"] = required
    audit["MODEL_CERTIFICATION_GATE"] = gate
    audit["CERTIFICATION_GAPS"] = failures
    audit["lineup_state_history_coverage"] = coverage
    audit["candidate_outputs"] = {
        "technical_history_rows_computed": history_count,
        "change_points_computed": cp_count,
        "historical_version_rows_computed": version_count,
        "temporal_patterns_computed": pattern_count,
        "technical_history_file": "AS_OF_FILTERED_HISTORY_UNCERTIFIED.csv",
        "change_point_file": "CHANGE_POINT_CANDIDATES_UNCERTIFIED.csv",
        "historical_version_file": "HISTORICAL_VERSION_CANDIDATES_UNCERTIFIED.csv",
        "pattern_file": "PATTERN_CANDIDATES_UNCERTIFIED.csv",
        "status": "DIAGNOSTIC_ONLY_NOT_AUTHORIZED",
    }
    audit["AS_OF_FILTERED_HISTORY_STATUS"] = "COMPUTED_NOT_CERTIFIED_FOR_CVD"
    audit["CHANGE_POINT_REGISTRY_STATUS"] = "NOT_AUTHORIZED"
    audit["HISTORICAL_VERSION_MAP_STATUS"] = "NOT_AUTHORIZED"
    audit["PATTERN_REGISTRY_STATUS"] = "NOT_AUTHORIZED"
    audit["HANDOFF_TO_CVD"] = "BLOCKED"
    audit["BHSSM_STATISTICAL_AUDIT"] = "FAIL"
    audit["BHSSM_EXECUTION_STATUS"] = "BLOCKED_BY_MODEL_CERTIFICATION"
    audit["AUTHORITY_FIREWALL"]["CANDIDATE_TECHNICAL_HISTORY"] = "DIAGNOSTIC_ONLY"
    audit["AUTHORITY_FIREWALL"]["CANDIDATE_CHANGE_POINTS"] = "DIAGNOSTIC_ONLY"
    audit["AUTHORITY_FIREWALL"]["CANDIDATE_HISTORICAL_VERSIONS"] = "DIAGNOSTIC_ONLY"
    audit["AUTHORITY_FIREWALL"]["CANDIDATE_PATTERNS"] = "DIAGNOSTIC_ONLY"

    config["status"] = "CANDIDATE_FROZEN_NOT_CERTIFIED"
    config["certification_gate"] = gate
    config["precommitted_before_current_game_analysis"] = False
    config["certification_gaps"] = failures

    dump_json(audit, AUDIT_PATH)
    dump_json(config, CONFIG_PATH)
    dump_json(
        {
            "MODEL_CERTIFICATION_GATE": gate,
            "required_tests": required,
            "gaps": failures,
            "authorized_change_points": 0,
            "authorized_historical_versions": 0,
            "authorized_temporal_patterns": 0,
            "candidate_change_points": cp_count,
            "candidate_historical_version_rows": version_count,
            "candidate_temporal_patterns": pattern_count,
            "technical_history_rows_computed": history_count,
            "handoff_to_cvd": "BLOCKED",
        },
        OUT / "MODEL_CERTIFICATION_GATE.json",
    )

    with REPORT_PATH.open("a", encoding="utf-8") as f:
        f.write("\n\n## Strict external certification gate\n\n")
        f.write(f"- MODEL_CERTIFICATION_GATE: **{gate}**\n")
        f.write("- BHSSM_STATISTICAL_AUDIT: **FAIL**\n")
        f.write("- BHSSM_EXECUTION_STATUS: **BLOCKED_BY_MODEL_CERTIFICATION**\n")
        f.write(f"- Technical-history rows computed: {history_count} (diagnostic/not certified for CVD)\n")
        f.write(f"- Diagnostic change-point candidates: {cp_count}\n")
        f.write(f"- Diagnostic historical-version rows: {version_count}\n")
        f.write(f"- Diagnostic temporal-pattern candidates: {pattern_count}\n")
        f.write("- Authorized CHANGE_POINT_REGISTRY rows: 0\n")
        f.write("- Authorized HISTORICAL_VERSION_MAP rows: 0\n")
        f.write("- Authorized PATTERN_REGISTRY rows: 0\n")
        f.write("- HANDOFF_TO_CVD: **BLOCKED**\n")
        f.write("- Certification gaps: " + ", ".join(failures) + "\n")
        if coverage["insufficient_history_batters"]:
            names = ", ".join(
                f"{r['batter']} ({r['technical_state_checkpoints']} checkpoints)"
                for r in coverage["insufficient_history_batters"]
            )
            f.write("- Insufficient state-history coverage: " + names + "\n")

    print(json.dumps({
        "MODEL_CERTIFICATION_GATE": gate,
        "gaps": failures,
        "candidate_change_points": cp_count,
        "candidate_version_rows": version_count,
        "candidate_patterns": pattern_count,
        "authorized_change_points": 0,
        "authorized_versions": 0,
        "authorized_patterns": 0,
        "insufficient_history_batters": coverage["insufficient_history_batters"],
        "execution": audit["BHSSM_EXECUTION_STATUS"],
    }, indent=2))


if __name__ == "__main__":
    main()
