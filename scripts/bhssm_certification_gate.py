#!/usr/bin/env python3
"""Strict post-execution certification gate for BHSSM.

This step separates successfully computed diagnostic candidates from outputs
that the BHSSM contract is allowed to certify. It intentionally fails closed:
if temporal validation, leakage, missing-data, regime, reclassification,
false-positive, false-negative, reproducibility, or threshold precommitment do
not all pass, candidate change points/versions remain diagnostic only and the
sovereign registries are emitted empty.
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
REPORT_PATH = OUT / "REPORT.md"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(obj, path: Path):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")


def preserve_candidates(path: Path, candidate_name: str):
    if not path.exists():
        return 0, []
    df = pd.read_csv(path)
    candidate_path = OUT / candidate_name
    df.to_csv(candidate_path, index=False)
    # Keep the sovereign registry schema but remove uncertified rows.
    pd.DataFrame(columns=df.columns).to_csv(path, index=False)
    return len(df), list(df.columns)


def main():
    audit = load_json(AUDIT_PATH)
    config = load_json(CONFIG_PATH)
    tests = dict(audit.get("tests", {}))

    # Contract-level certification tests. NO_FUTURE_DATA is the implemented
    # no-leakage/timestamp-firewall test in this runner.
    required = {
        "TEMPORAL_OUT_OF_SAMPLE_TEST": tests.get("TEMPORAL_OUT_OF_SAMPLE_TEST", "MISSING"),
        "NO_LEAKAGE_TEST": tests.get("NO_FUTURE_DATA", "MISSING"),
        "MISSING_DATA_TEST": tests.get("MISSING_DATA_TEST", "MISSING"),
        "REGIME_CHANGE_TEST": tests.get("REGIME_CHANGE_TEST", "MISSING"),
        "PITCH_RECLASSIFICATION_TEST": tests.get("PITCH_RECLASSIFICATION_TEST", "MISSING"),
        "FALSE_POSITIVE_TEST": tests.get("FALSE_POSITIVE_TEST", "MISSING"),
        "FALSE_NEGATIVE_TEST": tests.get("FALSE_NEGATIVE_TEST", "MISSING"),
        "REPRODUCIBILITY_TEST": tests.get("REPRODUCIBILITY_TEST", "MISSING"),
    }

    # The current config was selected/calibrated in this game-specific run.
    # It is reproducibly frozen after calibration, but it was not a separately
    # certified, pre-existing engine artifact before CIN@SF was analyzed.
    required["THRESHOLD_PRECOMMITMENT_TEST"] = "FAIL"

    # The execution log showed convergence warnings from the context logistic
    # models. Warnings do not invalidate raw ingestion, but a fully certified
    # context layer cannot be claimed until convergence is explicitly checked.
    required["CONTEXT_MODEL_CONVERGENCE_TEST"] = "LIMITED"

    failures = [k for k, v in required.items() if v != "PASS"]
    gate = "PASS" if not failures else "FAIL"

    cp_count, _ = preserve_candidates(
        CP_PATH, "CHANGE_POINT_CANDIDATES_UNCERTIFIED.csv"
    )
    version_count, _ = preserve_candidates(
        VM_PATH, "HISTORICAL_VERSION_CANDIDATES_UNCERTIFIED.csv"
    )

    audit["certification_tests"] = required
    audit["MODEL_CERTIFICATION_GATE"] = gate
    audit["CERTIFICATION_GAPS"] = failures
    audit["candidate_outputs"] = {
        "change_points_computed": cp_count,
        "historical_version_rows_computed": version_count,
        "change_point_file": "CHANGE_POINT_CANDIDATES_UNCERTIFIED.csv",
        "historical_version_file": "HISTORICAL_VERSION_CANDIDATES_UNCERTIFIED.csv",
        "status": "DIAGNOSTIC_ONLY_NOT_AUTHORIZED",
    }
    audit["CHANGE_POINT_REGISTRY_STATUS"] = "NOT_AUTHORIZED"
    audit["HISTORICAL_VERSION_MAP_STATUS"] = "NOT_AUTHORIZED"
    audit["HANDOFF_TO_CVD"] = "BLOCKED"
    audit["BHSSM_STATISTICAL_AUDIT"] = "FAIL"
    audit["BHSSM_EXECUTION_STATUS"] = "BLOCKED_BY_MODEL_CERTIFICATION"
    audit["AUTHORITY_FIREWALL"]["CANDIDATE_CHANGE_POINTS"] = "DIAGNOSTIC_ONLY"
    audit["AUTHORITY_FIREWALL"]["CANDIDATE_HISTORICAL_VERSIONS"] = "DIAGNOSTIC_ONLY"

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
            "candidate_change_points": cp_count,
            "candidate_historical_version_rows": version_count,
            "handoff_to_cvd": "BLOCKED",
        },
        OUT / "MODEL_CERTIFICATION_GATE.json",
    )

    with REPORT_PATH.open("a", encoding="utf-8") as f:
        f.write("\n\n## Strict certification gate\n\n")
        f.write(f"- MODEL_CERTIFICATION_GATE: **{gate}**\n")
        f.write("- BHSSM_STATISTICAL_AUDIT: **FAIL**\n")
        f.write("- BHSSM_EXECUTION_STATUS: **BLOCKED_BY_MODEL_CERTIFICATION**\n")
        f.write(f"- Diagnostic change-point candidates: {cp_count}\n")
        f.write(f"- Diagnostic historical-version rows: {version_count}\n")
        f.write("- Authorized CHANGE_POINT_REGISTRY rows: 0\n")
        f.write("- Authorized HISTORICAL_VERSION_MAP rows: 0\n")
        f.write("- HANDOFF_TO_CVD: **BLOCKED**\n")
        f.write("- Certification gaps: " + ", ".join(failures) + "\n")

    print(json.dumps({
        "MODEL_CERTIFICATION_GATE": gate,
        "gaps": failures,
        "candidate_change_points": cp_count,
        "candidate_version_rows": version_count,
        "authorized_change_points": 0,
        "authorized_versions": 0,
        "execution": audit["BHSSM_EXECUTION_STATUS"],
    }, indent=2))


if __name__ == "__main__":
    main()
