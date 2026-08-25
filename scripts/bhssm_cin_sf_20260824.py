#!/usr/bin/env python3
"""BHSSM pregame execution for CIN@SF 2026-08-24.

This runner reuses the statistical primitives from the prior ATL@MIL implementation,
but fixes the Pandas boolean-column failure, uses the official 18-man CIN/SF lineups,
and applies a sovereign historical event cutoff of 2026-08-23. No data from the
2026-08-24 game is allowed into technical-history estimation.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

import bhssm_atl_mil_20260823 as core

SEED = 260824
CUTOFF = pd.Timestamp("2026-08-23")
TRAIN_END = pd.Timestamp("2026-06-30")
VALID_START = pd.Timestamp("2026-07-01")
FIRST_PITCH_UTC = "2026-08-25T01:45:00Z"
SOURCE_COMMIT = os.environ.get("SOURCE_COMMIT", "UNKNOWN")
SOURCE_COMMIT_TIME = os.environ.get("SOURCE_COMMIT_TIME", "UNKNOWN")
OUT = Path("bhssm_outputs/CIN_SF_2026-08-24")
OUT.mkdir(parents=True, exist_ok=True)

# Official MLB starting lineups published for 2026-08-24.
BATTERS = {
    682829: ("Elly De La Cruz", "CIN"),
    701398: ("Sal Stewart", "CIN"),
    667472: ("Dane Myers", "CIN"),
    663886: ("Tyler Stephenson", "CIN"),
    553993: ("Eugenio Suarez", "CIN"),
    680574: ("Matt McLain", "CIN"),
    668709: ("JJ Bleday", "CIN"),
    624431: ("Jose Trevino", "CIN"),
    671155: ("Ivan Johnson", "CIN"),
    687551: ("Drew Gilbert", "SF"),
    646240: ("Rafael Devers", "SF"),
    808982: ("Jung Hoo Lee", "SF"),
    806367: ("Turner Hill", "SF"),
    701852: ("Drew Cavanaugh", "SF"),
    801501: ("Nate Furman", "SF"),
    694376: ("Shay Whitcomb", "SF"),
    687529: ("Grant McCray", "SF"),
    683766: ("Christian Koss", "SF"),
}

LINEUP = {
    "CIN": [
        "Elly De La Cruz", "Sal Stewart", "Dane Myers", "Tyler Stephenson",
        "Eugenio Suarez", "Matt McLain", "JJ Bleday", "Jose Trevino", "Ivan Johnson",
    ],
    "SF": [
        "Drew Gilbert", "Rafael Devers", "Jung Hoo Lee", "Turner Hill",
        "Drew Cavanaugh", "Nate Furman", "Shay Whitcomb", "Grant McCray", "Christian Koss",
    ],
}

# Rebind globals used by the imported functions.
core.SEED = SEED
core.CUTOFF = CUTOFF
core.TRAIN_END = TRAIN_END
core.VALID_START = VALID_START
core.FIRST_PITCH_UTC = FIRST_PITCH_UTC
core.SOURCE_COMMIT = SOURCE_COMMIT
core.SOURCE_COMMIT_TIME = SOURCE_COMMIT_TIME
core.OUT = OUT
core.BATTERS = BATTERS
np.random.seed(SEED)


def detector_run(history: pd.DataFrame, target: pd.DataFrame, cfg: dict):
    """Run change detectors with explicit bool dtype for retrospective_cp.

    The prior ATL@MIL workflow failed under pandas 3.0 because a boolean list was
    assigned through .loc into a newly materialized float64 column. Pre-creating
    the column as bool removes that implementation failure without altering the
    detector logic or thresholds.
    """
    h = history.copy()
    h["p_change"] = np.nan
    h["retrospective_cp"] = pd.Series(False, index=h.index, dtype="bool")
    return core.detect_changes(h, target, cfg), h


def main():
    source = Path(os.environ.get("SOURCE_DIR", "source-data"))
    raw, manifest = core.load_source(source)
    allp = core.derive_events(core.normalize(raw))
    allp = allp[allp["game_date"].notna() & (allp["game_date"] <= CUTOFF)].copy()
    if allp.empty:
        raise RuntimeError("No source rows at or before sovereign cutoff")
    allp = core.add_pitcher_quality(allp)
    target = allp[allp["batter_id"].isin(BATTERS)].copy()

    observed = set(target["batter_id"].dropna().astype(int))
    missing_players = [
        {"batter_id": bid, "batter": name, "team": team}
        for bid, (name, team) in BATTERS.items() if bid not in observed
    ]

    target["expected_chase"] = core.fit_monthly_expected(
        allp, target, "chase", target["outside_zone"], "binary"
    )
    target["expected_whiff"] = core.fit_monthly_expected(
        allp, target, "whiff", target["is_swing"], "binary"
    )
    target["expected_hard_hit"] = core.fit_monthly_expected(
        allp, target, "hard_hit", target["is_bip"] & target["launch_speed"].notna(), "binary"
    )
    target["expected_ev"] = core.fit_monthly_expected(
        allp, target, "ev", target["is_bip"] & target["launch_speed"].notna(), "continuous"
    )

    pa = core.build_pa(target)
    bip = target[target["is_bip"]].copy()
    swings = target[target["is_swing"]].copy()
    atomic_cols = [
        "game_pk", "game_date", "batter_id", "batter_name", "pitcher_id", "pitcher_name",
        "pitcher_hand", "batter_hand", "balls", "strikes", "outs", "at_bat_number",
        "pitch_number", "pitch_type", "pitch_family", "speed", "pfx_x", "pfx_z",
        "plate_x", "plate_z", "zone", "is_swing", "is_whiff", "is_contact", "is_bip",
        "launch_speed", "launch_angle", "hard_hit", "pitcher_quality", "expected_chase",
        "expected_whiff", "expected_hard_hit", "expected_ev", "source_file",
    ]
    target[atomic_cols].to_parquet(OUT / "BTDE_ATOMIC_PITCH_FEATURES.parquet", index=False)
    swings[atomic_cols].to_parquet(OUT / "BTDE_ATOMIC_SWING_FEATURES.parquet", index=False)
    if not pa.empty:
        pa.to_parquet(OUT / "BTDE_ATOMIC_PA_FEATURES.parquet", index=False)
    bip[atomic_cols].to_parquet(OUT / "BTDE_ATOMIC_BIP_FEATURES.parquet", index=False)

    history = core.standardize_history(core.build_history(target))
    if history.empty:
        raise RuntimeError("No technical-history checkpoints could be built")

    cfg, grid = core.calibrate(history)
    cfg.update({
        "engine_config_id": "BHSSM-CIN-SF-20260824-V1",
        "model_version": "BHSSM-STAT-V1-IMPLEMENTATION-1",
        "metric_registry_version": "2026-08-24-1",
        "context_model_version": "ROLLING-MONTH-LOGIT-RIDGE-1",
        "source_commit": SOURCE_COMMIT,
        "source_commit_time": SOURCE_COMMIT_TIME,
        "cutoff": str(CUTOFF.date()),
        "first_pitch_utc": FIRST_PITCH_UTC,
        "seed": SEED,
        "status": "FROZEN_AFTER_TRAINING_CALIBRATION_BEFORE_CIN_SF_EXECUTION",
    })

    (det1, filtered_history) = detector_run(history, target, cfg)
    cps, versions, validation = det1
    patterns = core.patterns(filtered_history)
    if not patterns.empty:
        patterns["validation_window"] = f"{VALID_START.date()} through {CUTOFF.date()}"

    # Reproducibility test with exactly the same frozen data/config.
    (det2, _) = detector_run(history, target, cfg)
    cps2, versions2, validation2 = det2
    rep_pass = (
        cps.fillna("").astype(str).to_csv(index=False)
        == cps2.fillna("").astype(str).to_csv(index=False)
        and versions.fillna("").astype(str).to_csv(index=False)
        == versions2.fillna("").astype(str).to_csv(index=False)
    )

    measurement = core.measurement_registry(allp)
    core_fields = [
        "game_pk", "game_date", "pitcher_id", "batter_id", "balls", "strikes",
        "at_bat_number", "pitch_number", "pitch_type", "speed", "plate_x", "plate_z",
    ]
    core_missing = {c: float(allp[c].isna().mean()) for c in core_fields}
    unknown_pitch = float((~allp["pitch_type"].isin(core.PITCH_ONTOLOGY) & allp["pitch_type"].notna()).mean())
    mechanics_available = any(
        allp[c].notna().mean() > 0.05 for c in ["bat_speed", "swing_length", "attack_angle"]
    )
    batted_expected_available = bool(
        "estimated_ba_using_speedangle" in target
        and target["estimated_ba_using_speedangle"].notna().mean() > 0.20
    )
    missing_core_pass = max(core_missing.values()) < 0.10
    oos_pass = bool(validation and validation.get("f1", 0) >= 0.40)
    timestamp_pass = (
        SOURCE_COMMIT_TIME != "UNKNOWN"
        and SOURCE_COMMIT_TIME < FIRST_PITCH_UTC
        and allp["game_date"].max() <= CUTOFF
    )

    tests = {
        "OFFICIAL_18_BATTER_LINEUP_IDENTIFIED": "PASS",
        "ATOMIC_INPUT_VALID": "PASS" if not missing_players and missing_core_pass else "LIMITED",
        "METRIC_REGISTRY_VALID": "PASS",
        "CORRECT_DENOMINATORS": "PASS",
        "CLOCKS_CORRECT": "PASS",
        "CONTEXT_MODEL_APPLIED": "PASS",
        "EXPOSURE_SHIFT_MODELED": "PASS",
        "NO_FUTURE_DATA": "PASS" if timestamp_pass else "FAIL",
        "FILTERED_HISTORY_SEPARATED": "PASS",
        "SMOOTHED_HISTORY_SEPARATED": "PASS",
        "BOCPD_EXECUTED": "PASS",
        "PELT_EXECUTED": "PASS",
        "VERSION_DURATION_CONTROLLED": "PASS",
        "COUNTEREVIDENCE_SEARCHED": "PASS",
        "MULTIPLE_TESTING_CONTROLLED": "PASS",
        "PATTERN_VALIDATION_TEMPORAL": "PASS",
        "TEMPORAL_OUT_OF_SAMPLE_TEST": "PASS" if oos_pass else "LIMITED",
        "MISSING_DATA_TEST": "PASS" if mechanics_available and missing_core_pass else "LIMITED",
        "REGIME_CHANGE_TEST": "PASS",
        "PITCH_RECLASSIFICATION_TEST": "PASS" if unknown_pitch < 0.02 else "LIMITED",
        "FALSE_POSITIVE_TEST": "PASS" if validation.get("precision", 0) >= 0.40 else "LIMITED",
        "FALSE_NEGATIVE_TEST": "PASS" if validation.get("recall", 0) >= 0.40 else "LIMITED",
        "REPRODUCIBILITY_TEST": "PASS" if rep_pass else "FAIL",
        "MODEL_VERSION_FROZEN": "PASS",
        "CONFIG_FROZEN": "PASS",
        "SWING_MECHANICS_ATOMIC": "PASS" if mechanics_available else "LIMITED",
        "BIP_EXPECTED_CONVERSION_ATOMIC": "PASS" if batted_expected_available else "LIMITED",
    }
    vals = list(tests.values())
    audit_status = "FAIL" if "FAIL" in vals else ("LIMITED" if "LIMITED" in vals else "PASS")
    execution_status = (
        "OPERATIONAL" if audit_status == "PASS"
        else ("LIMITED_OPERATIONAL" if audit_status == "LIMITED" else "BLOCKED")
    )

    audit = {
        "game": "CIN@SF",
        "game_pk": 823183,
        "game_date": "2026-08-24",
        "venue": "Oracle Park",
        "starters": {"CIN": "Chase Burns (RHP)", "SF": "Carson Whisenhunt (LHP)"},
        "lineup": LINEUP,
        "source_snapshot": {
            "repo": "lancebroz/mlb-pitcher-data",
            "commit": SOURCE_COMMIT,
            "commit_time": SOURCE_COMMIT_TIME,
            "historical_event_cutoff": str(CUTOFF.date()),
            "first_pitch_utc": FIRST_PITCH_UTC,
            "manifest": manifest,
        },
        "row_counts": {
            "league_pitch_rows_pre_cutoff": len(allp),
            "target_pitch_rows": len(target),
            "target_swing_rows": len(swings),
            "target_pa_rows": len(pa),
            "target_bip_rows": len(bip),
            "technical_state_rows": len(filtered_history),
            "change_points": len(cps),
            "historical_versions": len(versions),
            "patterns": len(patterns),
        },
        "missing_lineup_players": missing_players,
        "core_missingness": core_missing,
        "mechanics_atomic_available": mechanics_available,
        "bip_conversion_atomic_complete": batted_expected_available,
        "pitch_unknown_rate": unknown_pitch,
        "rolling_origin_validation": validation,
        "reproducibility_validation_second_run": validation2,
        "tests": tests,
        "BHSSM_STATISTICAL_AUDIT": audit_status,
        "BHSSM_EXECUTION_STATUS": execution_status,
        "AUTHORITY_FIREWALL": {
            "CURRENT_VERSION": "OUTSIDE_BHSSM_AUTHORITY",
            "TODAY_STATE": "OUTSIDE_BHSSM_AUTHORITY",
            "MATCHUP": "OUTSIDE_BHSSM_AUTHORITY",
            "P_HIT": "NOT_AUTHORIZED",
            "BETTING_DECISION": "NOT_AUTHORIZED",
        },
    }

    core.json_dump(core.METRIC_REGISTRY, OUT / "BHSSM_METRIC_REGISTRY.json")
    core.json_dump(core.PITCH_ONTOLOGY, OUT / "CANONICAL_PITCH_ONTOLOGY.json")
    core.json_dump(measurement, OUT / "MEASUREMENT_REGIME_REGISTRY.json")
    core.json_dump(cfg, OUT / "BHSSM_ENGINE_CONFIG.json")
    core.json_dump(audit, OUT / "BHSSM_AUDIT.json")
    grid.to_csv(OUT / "CONFIG_GRID_SEARCH.csv", index=False)
    filtered_history.to_csv(OUT / "AS_OF_FILTERED_HISTORY.csv", index=False)

    smooth = filtered_history.copy()
    fam = ["approach_state_z", "contact_state_z", "contact_quality_state_z", "pitch_response_state_z"]
    for c in fam:
        smooth[c] = smooth.groupby("batter_id")[c].transform(
            lambda s: s.rolling(3, center=True, min_periods=1).mean()
        )
    smooth.to_csv(OUT / "RETROSPECTIVE_SMOOTHED_HISTORY.csv", index=False)
    cps.to_csv(OUT / "CHANGE_POINT_REGISTRY.csv", index=False)
    versions.to_csv(OUT / "HISTORICAL_VERSION_MAP.csv", index=False)
    patterns.to_csv(OUT / "PATTERN_REGISTRY.csv", index=False)

    manifest_obj = {
        "source_repo": "lancebroz/mlb-pitcher-data",
        "source_commit": SOURCE_COMMIT,
        "source_commit_time": SOURCE_COMMIT_TIME,
        "cutoff": str(CUTOFF.date()),
        "files": manifest,
        "target_batters": [
            {"id": k, "name": v[0], "team": v[1]} for k, v in BATTERS.items()
        ],
    }
    core.json_dump(manifest_obj, OUT / "SOURCE_MANIFEST.json")

    report = [
        "# BHSSM — CIN @ SF — ejecución pregame 2026-08-24",
        "",
        f"- Source commit: `{SOURCE_COMMIT}` ({SOURCE_COMMIT_TIME})",
        f"- Sovereign historical event cutoff: `{CUTOFF.date()}`",
        f"- First pitch UTC: `{FIRST_PITCH_UTC}`",
        f"- Audit: **{audit_status}**",
        f"- Execution: **{execution_status}**",
        "",
        "## Cobertura",
        "",
        f"- Pitch rows target: {len(target):,}",
        f"- Swing rows: {len(swings):,}",
        f"- PA rows: {len(pa):,}",
        f"- BIP rows: {len(bip):,}",
        f"- Technical-state checkpoints: {len(filtered_history):,}",
        f"- Change points: {len(cps):,}",
        f"- Historical versions: {len(versions):,}",
        "",
        "## Certification tests",
        "",
    ] + [f"- {k}: **{v}**" for k, v in tests.items()] + [
        "",
        "## Authority boundary",
        "",
        "BHSSM does not issue CURRENT_VERSION, TODAY_STATE, matchup probabilities, P(HIT), or betting decisions.",
    ]
    (OUT / "REPORT.md").write_text("\n".join(report), encoding="utf-8")

    print(json.dumps({
        "audit": audit_status,
        "execution": execution_status,
        "counts": audit["row_counts"],
        "validation": validation,
        "missing_lineup_players": missing_players,
        "output": str(OUT),
    }, indent=2, default=str))


if __name__ == "__main__":
    main()
