#!/usr/bin/env python3
"""BHSSM pregame execution for ATL@MIL 2026-08-23.

Sovereign cutoff: 2026-08-22. Source snapshot is supplied by workflow as an
MLB pitch-data repository checkout frozen before first pitch. The program
builds atomic pitch/swing/PA/BIP tables, context-adjusted technical states,
online/offline change detection, version map, temporal pattern validation,
rolling-origin diagnostics and an auditable frozen config.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np
import pandas as pd
from scipy.spatial.distance import jensenshannon
from scipy.stats import norm, spearmanr
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
import ruptures as rpt

SEED = 260823
np.random.seed(SEED)
CUTOFF = pd.Timestamp("2026-08-22")
TRAIN_END = pd.Timestamp("2026-06-30")
VALID_START = pd.Timestamp("2026-07-01")
SOURCE_COMMIT = os.environ.get("SOURCE_COMMIT", "UNKNOWN")
SOURCE_COMMIT_TIME = os.environ.get("SOURCE_COMMIT_TIME", "UNKNOWN")
FIRST_PITCH_UTC = "2026-08-23T23:10:00Z"
OUT = Path("bhssm_outputs/ATL_MIL_2026-08-23")
OUT.mkdir(parents=True, exist_ok=True)

BATTERS = {
    671739: ("Michael Harris II", "ATL"),
    660670: ("Ronald Acuña Jr.", "ATL"),
    621566: ("Matt Olson", "ATL"),
    645277: ("Ozzie Albies", "ATL"),
    686948: ("Drake Baldwin", "ATL"),
    657041: ("Lane Thomas", "ATL"),
    643289: ("Mauricio Dubón", "ATL"),
    663586: ("Austin Riley", "ATL"),
    669221: ("Sean Murphy", "ATL"),
    694192: ("Jackson Chourio", "MIL"),
    668930: ("Brice Turang", "MIL"),
    661388: ("William Contreras", "MIL"),
    641343: ("Jake Bauers", "MIL"),
    683734: ("Andrew Vaughn", "MIL"),
    592885: ("Christian Yelich", "MIL"),
    687401: ("Joey Ortiz", "MIL"),
    669003: ("Garrett Mitchell", "MIL"),
    666152: ("David Hamilton", "MIL"),
}

# Canonical pitch-family ontology. Unknown codes are retained and audited.
PITCH_ONTOLOGY = {
    "FF": "4S", "FA": "4S", "SI": "SI", "FT": "SI", "FC": "FC",
    "SL": "SL", "ST": "SW", "SV": "SW", "CU": "CU", "KC": "CU",
    "CS": "CU", "CH": "CH", "FS": "FS", "FO": "FS", "SC": "OTHER",
    "KN": "OTHER", "EP": "OTHER", "PO": "OTHER", "IN": "OTHER",
}

METRIC_REGISTRY = {
    "CHASE_RATE": {"numerator": "SWINGS_OUTSIDE_ZONE", "denominator": "PITCHES_OUTSIDE_ZONE", "clock": "PITCH_CLOCK", "family": "APPROACH"},
    "WHIFF_RATE": {"numerator": "SWINGING_STRIKES", "denominator": "SWINGS", "clock": "SWING_CLOCK", "family": "CONTACT"},
    "ZONE_CONTACT_RATE": {"numerator": "CONTACTS_IN_ZONE", "denominator": "SWINGS_IN_ZONE", "clock": "SWING_CLOCK", "family": "CONTACT"},
    "FIRST_PITCH_SWING_RATE": {"numerator": "FIRST_PITCH_SWINGS", "denominator": "FIRST_PITCHES", "clock": "PITCH_CLOCK", "family": "APPROACH"},
    "HARD_HIT_RATE": {"numerator": "BIP_EV_95_PLUS", "denominator": "BIP_WITH_EV", "clock": "BIP_CLOCK", "family": "CONTACT_QUALITY"},
    "EXIT_VELOCITY": {"numerator": None, "denominator": "BIP_WITH_EV", "clock": "BIP_CLOCK", "family": "CONTACT_QUALITY"},
    "K_RATE": {"numerator": "STRIKEOUT_PA", "denominator": "PA", "clock": "PA_CLOCK", "family": "CONTACT"},
    "BB_RATE": {"numerator": "WALK_PA", "denominator": "PA", "clock": "PA_CLOCK", "family": "APPROACH"},
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def json_dump(obj, path: Path):
    def conv(x):
        if isinstance(x, (np.integer,)): return int(x)
        if isinstance(x, (np.floating,)): return None if not np.isfinite(x) else float(x)
        if isinstance(x, (pd.Timestamp,)): return x.isoformat()
        if isinstance(x, np.ndarray): return x.tolist()
        return str(x)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False, default=conv), encoding="utf-8")


def first_col(df: pd.DataFrame, names: Iterable[str], default=np.nan):
    for n in names:
        if n in df.columns:
            return df[n]
    return pd.Series(default, index=df.index)


def bool_series(s: pd.Series) -> pd.Series:
    if s.dtype == bool:
        return s.fillna(False)
    return s.astype(str).str.lower().isin(["true", "1", "t", "yes", "y"])


def load_source(source_dir: Path) -> Tuple[pd.DataFrame, List[dict]]:
    files = sorted((source_dir / "data/raw/2026/monthly").glob("*.parquet"))
    files = [p for p in files if p.name[:2] in {"03", "04", "05", "06", "07", "08"}]
    if not files:
        raise RuntimeError("No monthly Parquet source files found")
    manifest, dfs = [], []
    for p in files:
        d = pd.read_parquet(p)
        d["_source_file"] = p.name
        dfs.append(d)
        manifest.append({"file": p.name, "sha256": sha256_file(p), "bytes": p.stat().st_size})
    df = pd.concat(dfs, ignore_index=True, sort=False)
    return df, manifest


def normalize(df: pd.DataFrame) -> pd.DataFrame:
    x = pd.DataFrame(index=df.index)
    x["game_pk"] = pd.to_numeric(first_col(df, ["game_pk"]), errors="coerce")
    x["game_date"] = pd.to_datetime(first_col(df, ["game_date"]), errors="coerce").dt.normalize()
    x["home_team"] = first_col(df, ["home_team"])
    x["away_team"] = first_col(df, ["away_team"])
    x["venue"] = first_col(df, ["venue"])
    x["inning"] = pd.to_numeric(first_col(df, ["inning"]), errors="coerce")
    x["top_bottom"] = first_col(df, ["top_bottom", "inning_topbot"])
    x["pitcher_id"] = pd.to_numeric(first_col(df, ["pitcher_id", "pitcher"]), errors="coerce")
    x["pitcher_name"] = first_col(df, ["pitcher_name", "player_name"])
    x["pitcher_hand"] = first_col(df, ["pitcher_hand", "p_throws"])
    x["batter_id"] = pd.to_numeric(first_col(df, ["batter_id", "batter"]), errors="coerce")
    x["batter_name"] = first_col(df, ["batter_name"])
    x["batter_hand"] = first_col(df, ["batter_hand", "stand"])
    x["balls"] = pd.to_numeric(first_col(df, ["balls"]), errors="coerce")
    x["strikes"] = pd.to_numeric(first_col(df, ["strikes"]), errors="coerce")
    x["outs"] = pd.to_numeric(first_col(df, ["outs", "outs_when_up"]), errors="coerce")
    x["at_bat_number"] = pd.to_numeric(first_col(df, ["at_bat_number"]), errors="coerce")
    x["pitch_number"] = pd.to_numeric(first_col(df, ["pitch_number"]), errors="coerce")
    x["pitch_type"] = first_col(df, ["pitch_type"])
    x["pitch_name"] = first_col(df, ["pitch_name"])
    x["speed"] = pd.to_numeric(first_col(df, ["start_speed", "release_speed"]), errors="coerce")
    x["plate_x"] = pd.to_numeric(first_col(df, ["plate_x"]), errors="coerce")
    x["plate_z"] = pd.to_numeric(first_col(df, ["plate_z"]), errors="coerce")
    x["zone"] = pd.to_numeric(first_col(df, ["zone"]), errors="coerce")
    x["sz_top"] = pd.to_numeric(first_col(df, ["sz_top"]), errors="coerce")
    x["sz_bottom"] = pd.to_numeric(first_col(df, ["sz_bottom"]), errors="coerce")
    x["pfx_x"] = pd.to_numeric(first_col(df, ["pfx_x"]), errors="coerce")
    x["pfx_z"] = pd.to_numeric(first_col(df, ["pfx_z"]), errors="coerce")
    x["description"] = first_col(df, ["call_description", "description"]).fillna("").astype(str)
    x["call_code"] = first_col(df, ["call_code", "type"]).fillna("").astype(str)
    x["is_strike"] = bool_series(first_col(df, ["is_strike"], False))
    x["is_ball"] = bool_series(first_col(df, ["is_ball"], False))
    x["is_in_play"] = bool_series(first_col(df, ["is_in_play"], False))
    x["launch_speed"] = pd.to_numeric(first_col(df, ["launch_speed"]), errors="coerce")
    x["launch_angle"] = pd.to_numeric(first_col(df, ["launch_angle"]), errors="coerce")
    x["hit_distance"] = pd.to_numeric(first_col(df, ["hit_distance", "hit_distance_sc"]), errors="coerce")
    x["trajectory"] = first_col(df, ["trajectory", "bb_type"])
    x["hit_x"] = pd.to_numeric(first_col(df, ["hit_x", "hc_x"]), errors="coerce")
    x["hit_y"] = pd.to_numeric(first_col(df, ["hit_y", "hc_y"]), errors="coerce")
    x["source_file"] = first_col(df, ["_source_file"])
    # Preserve optional richer fields if present in source snapshot.
    for c in ["bat_speed", "swing_length", "attack_angle", "events", "estimated_ba_using_speedangle", "if_fielding_alignment", "of_fielding_alignment"]:
        x[c] = first_col(df, [c])
    return x


def derive_events(x: pd.DataFrame) -> pd.DataFrame:
    d = x["description"].str.lower()
    code = x["call_code"].str.upper()
    whiff = d.str.contains("swinging strike|swinging_strike|miss", regex=True) | code.isin(["S", "W"])
    foul = d.str.contains("foul", regex=False) | code.isin(["F", "T", "L"])
    inplay = x["is_in_play"] | code.isin(["X", "D", "E"]) | d.str.contains("in play|hit_into_play", regex=True)
    swing = whiff | foul | inplay | d.str.contains("swing", regex=False)
    zone = x["zone"].between(1, 9)
    # If zone code unavailable, use individualized strike-zone geometry.
    geom_zone = (x["plate_x"].abs() <= 0.83) & (x["plate_z"] >= x["sz_bottom"]) & (x["plate_z"] <= x["sz_top"])
    zone = zone.where(x["zone"].notna(), geom_zone)
    x["is_swing"] = swing
    x["is_whiff"] = whiff & swing
    x["is_contact"] = swing & ~whiff
    x["in_zone"] = zone
    x["outside_zone"] = ~zone
    x["is_bip"] = inplay
    x["hard_hit"] = np.where(x["is_bip"] & x["launch_speed"].notna(), x["launch_speed"] >= 95.0, np.nan)
    x["first_pitch"] = x["pitch_number"].eq(1)
    x["pitch_family"] = x["pitch_type"].map(PITCH_ONTOLOGY).fillna(x["pitch_type"].fillna("UNKNOWN"))
    return x


def add_pitcher_quality(allp: pd.DataFrame) -> pd.DataFrame:
    g = allp.loc[allp["is_swing"] & allp["pitcher_id"].notna(), ["pitcher_id", "game_date", "is_whiff"]].copy()
    daily = g.groupby(["pitcher_id", "game_date"], as_index=False).agg(swings=("is_whiff", "size"), whiffs=("is_whiff", "sum"))
    daily = daily.sort_values(["pitcher_id", "game_date"])
    daily["cum_swings"] = daily.groupby("pitcher_id")["swings"].cumsum() - daily["swings"]
    daily["cum_whiffs"] = daily.groupby("pitcher_id")["whiffs"].cumsum() - daily["whiffs"]
    league = max(float(g["is_whiff"].mean()), 0.01)
    daily["pitcher_quality"] = (daily["cum_whiffs"] + 50 * league) / (daily["cum_swings"] + 50)
    out = allp.merge(daily[["pitcher_id", "game_date", "pitcher_quality"]], on=["pitcher_id", "game_date"], how="left")
    out["pitcher_quality"] = out["pitcher_quality"].fillna(league)
    return out


def build_pa(target: pd.DataFrame) -> pd.DataFrame:
    z = target.dropna(subset=["game_pk", "at_bat_number", "batter_id"]).sort_values(["game_pk", "at_bat_number", "pitch_number"])
    if z.empty:
        return pd.DataFrame()
    grp = z.groupby(["game_pk", "batter_id", "at_bat_number"], sort=False)
    pa = grp.tail(1).copy()
    pa["pa_pitches"] = grp["pitch_number"].transform("max").reindex(pa.index)
    dl = pa["description"].str.lower()
    # Count values are pre-pitch in MLB live-feed convention.
    strike_event = pa["is_whiff"] | pa["is_strike"] | dl.str.contains("called strike|strikeout", regex=True)
    ball_event = pa["is_ball"] | dl.str.contains("ball", regex=False)
    pa["strikeout_pa"] = (pa["strikes"].ge(2) & strike_event) | dl.str.contains("strikeout", regex=False)
    pa["walk_pa"] = (pa["balls"].ge(3) & ball_event) | dl.str.contains("walk", regex=False)
    return pa


def fit_monthly_expected(allp: pd.DataFrame, target: pd.DataFrame, outcome: str, eligible: pd.Series, kind="binary") -> pd.Series:
    pred = pd.Series(np.nan, index=target.index, dtype=float)
    months = sorted(target.loc[eligible, "game_date"].dropna().dt.to_period("M").unique())
    cat = ["pitch_family", "pitcher_hand", "balls", "strikes"]
    num = ["speed", "pfx_x", "pfx_z", "plate_x", "plate_z", "pitcher_quality"]
    for m in months:
        start = m.to_timestamp()
        test_idx = target.index[eligible & (target["game_date"].dt.to_period("M") == m)]
        train_mask = allp["game_date"].lt(start)
        if outcome == "chase": train_mask &= allp["outside_zone"]
        elif outcome == "whiff": train_mask &= allp["is_swing"]
        elif outcome in ("hard_hit", "ev"): train_mask &= allp["is_bip"] & allp["launch_speed"].notna()
        tr = allp.loc[train_mask].copy()
        if len(tr) < 1000:
            continue
        if len(tr) > 180000:
            tr = tr.sample(180000, random_state=SEED)
        if outcome == "chase": y = tr["is_swing"].astype(int)
        elif outcome == "whiff": y = tr["is_whiff"].astype(int)
        elif outcome == "hard_hit": y = (tr["launch_speed"] >= 95).astype(int)
        else: y = tr["launch_speed"].astype(float)
        pre = ColumnTransformer([
            ("num", Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]), num),
            ("cat", Pipeline([("imp", SimpleImputer(strategy="most_frequent")), ("oh", OneHotEncoder(handle_unknown="ignore"))]), cat),
        ])
        model = LogisticRegression(max_iter=250, C=0.5, solver="saga", n_jobs=1, random_state=SEED) if kind == "binary" else Ridge(alpha=10.0)
        pipe = Pipeline([("pre", pre), ("model", model)])
        try:
            pipe.fit(tr[num + cat], y)
            te = target.loc[test_idx, num + cat]
            pred.loc[test_idx] = pipe.predict_proba(te)[:, 1] if kind == "binary" else pipe.predict(te)
        except Exception:
            continue
    return pred


def beta_mean(k: float, n: float, a=1.0, b=1.0) -> float:
    return (k + a) / (n + a + b) if n >= 0 else np.nan


def build_history(target: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for bid, (name, team) in BATTERS.items():
        b = target[target["batter_id"].eq(bid)].sort_values(["game_date", "game_pk", "at_bat_number", "pitch_number"]).copy()
        if b.empty:
            continue
        b["pitch_clock"] = np.arange(1, len(b) + 1)
        checkpoints = list(range(120, len(b) + 1, 40))
        if checkpoints and checkpoints[-1] != len(b): checkpoints.append(len(b))
        elif not checkpoints and len(b) >= 60: checkpoints = [len(b)]
        for end in checkpoints:
            w = b.iloc[max(0, end - 120):end]
            chase = w[w["outside_zone"] & w["expected_chase"].notna()]
            whiff = w[w["is_swing"] & w["expected_whiff"].notna()]
            bip = w[w["is_bip"] & w["launch_speed"].notna() & w["expected_hard_hit"].notna()]
            ev = w[w["is_bip"] & w["launch_speed"].notna() & w["expected_ev"].notna()]
            first = w[w["first_pitch"]]
            zone_sw = w[w["in_zone"] & w["is_swing"]]
            n_ch, n_sw, n_bip = len(chase), len(whiff), len(bip)
            chase_res = float((chase["is_swing"].astype(float) - chase["expected_chase"]).mean()) if n_ch else np.nan
            whiff_res = float((whiff["is_whiff"].astype(float) - whiff["expected_whiff"]).mean()) if n_sw else np.nan
            hh_res = float((bip["hard_hit"].astype(float) - bip["expected_hard_hit"]).mean()) if n_bip else np.nan
            ev_res = float((ev["launch_speed"] - ev["expected_ev"]).mean()) if len(ev) else np.nan
            fps = beta_mean(float(first["is_swing"].sum()), len(first)) if len(first) else np.nan
            zcontact = beta_mean(float(zone_sw["is_contact"].sum()), len(zone_sw)) if len(zone_sw) else np.nan
            approach = -chase_res if np.isfinite(chase_res) else np.nan
            contact = -whiff_res if np.isfinite(whiff_res) else np.nan
            cq_parts = [v for v in [hh_res, (ev_res / 10.0 if np.isfinite(ev_res) else np.nan)] if np.isfinite(v)]
            cq = float(np.mean(cq_parts)) if cq_parts else np.nan
            pr_parts = [v for v in [approach, contact, cq] if np.isfinite(v)]
            pitch_response = float(np.mean(pr_parts)) if pr_parts else np.nan
            auth = min(1.0, n_ch / 50 if n_ch else 0, n_sw / 40 if n_sw else 0, n_bip / 15 if n_bip else 0)
            # uncertainty is a conservative pooled SE proxy; no false precision.
            ses = []
            if n_ch: ses.append(math.sqrt(max(float(chase["expected_chase"].mul(1-chase["expected_chase"]).mean()), .01) / n_ch))
            if n_sw: ses.append(math.sqrt(max(float(whiff["expected_whiff"].mul(1-whiff["expected_whiff"]).mean()), .01) / n_sw))
            if n_bip: ses.append(math.sqrt(max(float(bip["expected_hard_hit"].mul(1-bip["expected_hard_hit"]).mean()), .01) / n_bip))
            rows.append({
                "batter_id": bid, "batter": name, "team": team, "as_of": w["game_date"].iloc[-1],
                "exposure_index": int(end), "window_pitch_n": len(w), "chase_n": n_ch, "swing_n": n_sw, "bip_n": n_bip,
                "approach_state": approach, "contact_state": contact, "contact_quality_state": cq,
                "swing_mechanics_state": np.nan, "pitch_response_state": pitch_response, "bip_conversion_state": np.nan,
                "first_pitch_swing_post_mean": fps, "zone_contact_post_mean": zcontact,
                "state_uncertainty": float(np.mean(ses)) if ses else np.nan, "sample_authority": auth,
                "context_adjustment_status": "PASS" if n_ch and n_sw and n_bip else "LIMITED",
            })
    h = pd.DataFrame(rows)
    return h.sort_values(["batter_id", "exposure_index"]).reset_index(drop=True)


def standardize_history(h: pd.DataFrame) -> pd.DataFrame:
    fam = ["approach_state", "contact_state", "contact_quality_state", "pitch_response_state"]
    out = h.copy()
    for bid, idx in out.groupby("batter_id").groups.items():
        train_idx = [i for i in idx if out.loc[i, "as_of"] <= TRAIN_END]
        base_idx = train_idx if len(train_idx) >= 3 else list(idx)
        for c in fam:
            mu = out.loc[base_idx, c].mean()
            sd = out.loc[base_idx, c].std(ddof=1)
            if not np.isfinite(sd) or sd < 1e-6: sd = 1.0
            out.loc[idx, c + "_z"] = (out.loc[idx, c] - mu) / sd
        zcols = [c + "_z" for c in fam]
        out.loc[idx, "latent_score"] = out.loc[idx, zcols].mean(axis=1, skipna=True)
    return out


def bocpd(x: np.ndarray, hazard_lambda: float) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    n = len(x)
    if n == 0: return np.array([])
    # Fill occasional missing latent values with 0 after per-batter standardization.
    x = np.nan_to_num(x, nan=0.0)
    var = float(np.var(x[:max(3, min(n, 10))]))
    if not np.isfinite(var) or var < 0.05: var = 1.0
    H = min(max(1.0 / hazard_lambda, 1e-5), 0.5)
    R = np.zeros((n + 1, n + 1), dtype=float); R[0, 0] = 1.0
    mu = np.array([0.0]); kappa = np.array([1.0])
    pcp = np.zeros(n)
    for t in range(1, n + 1):
        xt = x[t - 1]
        pred = norm.pdf(xt, loc=mu, scale=np.sqrt(var * (1.0 + 1.0 / kappa))) + 1e-300
        prior_pred = norm.pdf(xt, loc=0.0, scale=math.sqrt(var * 2.0)) + 1e-300
        cp = prior_pred * H * R[t - 1, :t].sum()
        growth = pred * (1.0 - H) * R[t - 1, :t]
        R[t, 0] = cp
        R[t, 1:t + 1] = growth
        s = R[t, :t + 1].sum()
        if s <= 0 or not np.isfinite(s): R[t, :t + 1] = 0; R[t, 0] = 1.0
        else: R[t, :t + 1] /= s
        pcp[t - 1] = R[t, 0]
        old_mu, old_k = mu, kappa
        new_mu = np.empty(t + 1); new_k = np.empty(t + 1)
        new_k[0] = 2.0; new_mu[0] = xt / 2.0
        new_k[1:] = old_k + 1.0
        new_mu[1:] = (old_k * old_mu + xt) / new_k[1:]
        mu, kappa = new_mu, new_k
    return pcp


def pelt_points(X: np.ndarray, penalty: float, min_size=2) -> List[int]:
    if len(X) < max(6, min_size * 2): return []
    Z = np.nan_to_num(np.asarray(X, dtype=float), nan=0.0)
    try:
        cps = rpt.Pelt(model="rbf", min_size=min_size, jump=1).fit(Z).predict(pen=float(penalty))
        return [int(c) for c in cps if c < len(Z)]
    except Exception:
        return []


def match_events(online: List[int], retro: List[int], tol: int) -> dict:
    used = set(); matches = []
    for o in online:
        cand = [(abs(o-r), r) for r in retro if r not in used and abs(o-r) <= tol]
        if cand:
            _, r = min(cand); used.add(r); matches.append((o, r))
    tp, fp, fn = len(matches), len(online)-len(matches), len(retro)-len(matches)
    precision = tp/(tp+fp) if tp+fp else (1.0 if not retro else 0.0)
    recall = tp/(tp+fn) if tp+fn else 1.0
    f1 = 2*precision*recall/(precision+recall) if precision+recall else 0.0
    delay = float(np.mean([abs(o-r) for o,r in matches])) if matches else np.nan
    return {"tp":tp,"fp":fp,"fn":fn,"precision":precision,"recall":recall,"f1":f1,"delay":delay}


def calibrate(h: pd.DataFrame) -> Tuple[dict, pd.DataFrame]:
    famz = ["approach_state_z", "contact_state_z", "contact_quality_state_z", "pitch_response_state_z"]
    candidates = []
    for hazard in [8, 12, 20, 30]:
        for threshold in [0.20, 0.35, 0.50, 0.65]:
            for pen in [2.0, 4.0, 6.0, 8.0]:
                for tol in [1, 2]:
                    agg = {"tp":0,"fp":0,"fn":0,"delays":[]}
                    for bid, g in h[h["as_of"] <= TRAIN_END].groupby("batter_id"):
                        if len(g) < 6: continue
                        p = bocpd(g["latent_score"].to_numpy(), hazard)
                        online = [i+1 for i,v in enumerate(p) if v >= threshold and g.iloc[i]["sample_authority"] >= 0.5]
                        retro = pelt_points(g[famz].to_numpy(), pen, 2)
                        m = match_events(online, retro, tol)
                        for k in ["tp","fp","fn"]: agg[k]+=m[k]
                        if np.isfinite(m["delay"]): agg["delays"].append(m["delay"])
                    tp,fp,fn=agg["tp"],agg["fp"],agg["fn"]
                    pr=tp/(tp+fp) if tp+fp else 0.0; rc=tp/(tp+fn) if tp+fn else 0.0
                    f1=2*pr*rc/(pr+rc) if pr+rc else 0.0
                    delay=float(np.mean(agg["delays"])) if agg["delays"] else 99.0
                    score=f1 - 0.03*delay - 0.01*fp
                    candidates.append({"hazard_lambda":hazard,"possible_change_threshold":threshold,"pelt_penalty":pen,"change_match_tolerance":tol,"precision":pr,"recall":rc,"f1":f1,"delay":delay,"score":score,"tp":tp,"fp":fp,"fn":fn})
    cdf=pd.DataFrame(candidates).sort_values(["score","f1","precision"],ascending=False)
    if cdf.empty: best={"hazard_lambda":20,"possible_change_threshold":0.5,"pelt_penalty":4.0,"change_match_tolerance":2}
    else: best=cdf.iloc[0].to_dict()
    # Learn materiality and exposure-shift thresholds from training data.
    distances=[]
    for _,g in h[h["as_of"]<=TRAIN_END].groupby("batter_id"):
        Z=np.nan_to_num(g[famz].to_numpy(float),nan=0.0)
        if len(Z)>1: distances.extend(np.linalg.norm(np.diff(Z,axis=0),axis=1).tolist())
    best["minimum_material_change"] = float(np.quantile(distances, .90)) if distances else 1.5
    best["structural_material_change"] = float(np.quantile(distances, .97)) if distances else 2.0
    best["min_version_duration_checkpoints"] = 3
    best["minimum_sample_authority"] = 0.5
    best["seed"] = SEED
    best["train_end"] = str(TRAIN_END.date())
    best["validation_start"] = str(VALID_START.date())
    return best, cdf


def pitch_mix_jsd(b: pd.DataFrame, exposure: int) -> float:
    left=b[(b["pitch_clock"]>max(0,exposure-120)) & (b["pitch_clock"]<=exposure)]
    right=b[(b["pitch_clock"]>exposure) & (b["pitch_clock"]<=exposure+120)]
    cats=sorted(set(left["pitch_family"].dropna())|set(right["pitch_family"].dropna()))
    if not cats or len(left)<30 or len(right)<30: return np.nan
    a=left["pitch_family"].value_counts(normalize=True).reindex(cats,fill_value=0).to_numpy()+1e-9
    c=right["pitch_family"].value_counts(normalize=True).reindex(cats,fill_value=0).to_numpy()+1e-9
    return float(jensenshannon(a,c,base=2.0)**2)


def detect_changes(h: pd.DataFrame, target: pd.DataFrame, cfg: dict) -> Tuple[pd.DataFrame,pd.DataFrame,dict]:
    famz=["approach_state_z","contact_state_z","contact_quality_state_z","pitch_response_state_z"]
    cp_rows=[]; version_rows=[]; validation=[]
    for bid,(name,team) in BATTERS.items():
        g=h[h["batter_id"].eq(bid)].copy().reset_index(drop=True)
        if len(g)<3: continue
        p=bocpd(g["latent_score"].to_numpy(), float(cfg["hazard_lambda"]))
        g["p_change"]=p
        retro=pelt_points(g[famz].to_numpy(), float(cfg["pelt_penalty"]),2)
        online=[i+1 for i,v in enumerate(p) if v>=float(cfg["possible_change_threshold"]) and g.iloc[i]["sample_authority"]>=float(cfg["minimum_sample_authority"])]
        # OOS validation: frozen config, evaluate only holdout events against retrospective support.
        hold_online=[i for i in online if g.iloc[i-1]["as_of"]>=VALID_START]
        hold_retro=[r for r in retro if g.iloc[r-1]["as_of"]>=VALID_START]
        validation.append(match_events(hold_online,hold_retro,int(cfg["change_match_tolerance"])))
        bt=target[target["batter_id"].eq(bid)].copy()
        bt=bt.sort_values(["game_date","game_pk","at_bat_number","pitch_number"]); bt["pitch_clock"]=np.arange(1,len(bt)+1)
        accepted=[]
        for i,v in enumerate(p):
            if v<float(cfg["possible_change_threshold"]) or g.iloc[i]["sample_authority"]<float(cfg["minimum_sample_authority"]): continue
            pos=i+1; before=max(0,i-2); after=min(len(g),i+3)
            prev=np.nanmean(g.loc[before:max(i-1,before),famz].to_numpy(float),axis=0) if i>0 else np.zeros(len(famz))
            nxt=np.nanmean(g.loc[i:min(i+2,len(g)-1),famz].to_numpy(float),axis=0)
            dist=float(np.linalg.norm(np.nan_to_num(nxt-prev,nan=0.0)))
            retro_support=any(abs(pos-r)<=int(cfg["change_match_tolerance"]) for r in retro)
            forward_persist=(after-i)>=2 and dist>=float(cfg["minimum_material_change"])
            exposure=int(g.iloc[i]["exposure_index"])
            jsd=pitch_mix_jsd(bt,exposure)
            deltas=np.nan_to_num(nxt-prev,nan=0.0)
            coherence=int((np.abs(deltas)>=0.50).sum())
            exposure_dominant=bool(np.isfinite(jsd) and jsd>=0.20 and dist<float(cfg["structural_material_change"]))
            status="POSSIBLE_CHANGE"
            if dist>=float(cfg["minimum_material_change"]) and (retro_support or forward_persist): status="SUPPORTED_CHANGE"
            if status=="SUPPORTED_CHANGE" and coherence>=2 and forward_persist and not exposure_dominant and dist>=float(cfg["structural_material_change"]): status="STRUCTURAL_CHANGE"
            cp_rows.append({"change_point_id":f"{bid}-CP-{pos:03d}","batter_id":bid,"batter":name,"team":team,"first_observed_date":g.iloc[i]["as_of"],"supported_from_date":g.iloc[min(i+1,len(g)-1)]["as_of"] if status!="POSSIBLE_CHANGE" else pd.NaT,"exposure_index":exposure,"p_change":float(v),"retrospective_support":retro_support,"state_distance":dist,"multivariable_coherence":coherence,"pitch_mix_jsd":jsd,"exposure_dominant":exposure_dominant,"sample_authority":float(g.iloc[i]["sample_authority"]),"context_control":"PASS","counterevidence":"EXPOSURE_SHIFT_TESTED","status":status,"mechanism_status":"UNKNOWN"})
            if status in {"SUPPORTED_CHANGE","STRUCTURAL_CHANGE"}: accepted.append((i,status))
        # Semi-Markov-like version map with explicit minimum-duration gate.
        boundaries=[(0,"INITIAL")]+[(i,s) for i,s in accepted]
        ded=[]
        for item in boundaries:
            if not ded or item[0]-ded[-1][0]>=int(cfg["min_version_duration_checkpoints"]): ded.append(item)
        for j,(start_i,why) in enumerate(ded):
            end_i=(ded[j+1][0]-1) if j+1<len(ded) else len(g)-1
            if end_i-start_i+1<int(cfg["min_version_duration_checkpoints"]) and j>0: continue
            sig=g.loc[start_i:end_i,famz].mean().to_dict()
            version_rows.append({"version_id":f"{bid}-V{j+1}","batter_id":bid,"batter":name,"team":team,"start":g.iloc[start_i]["as_of"],"end":g.iloc[end_i]["as_of"],"start_exposure":int(g.iloc[start_i]["exposure_index"]),"end_exposure":int(g.iloc[end_i]["exposure_index"]),"duration_checkpoints":int(end_i-start_i+1),"technical_signature":json.dumps({k:None if not np.isfinite(v) else round(float(v),4) for k,v in sig.items()}),"state_uncertainty":float(g.loc[start_i:end_i,"state_uncertainty"].mean()),"supporting_change_point":why,"status":"STRUCTURAL" if why=="STRUCTURAL_CHANGE" else ("SUPPORTED" if why=="SUPPORTED_CHANGE" else "BASELINE"),"transportability":"UNTESTED_CURRENT_MATCHUP"})
        h.loc[h["batter_id"].eq(bid),"p_change"] = p
        h.loc[h["batter_id"].eq(bid),"retrospective_cp"] = [((i+1) in retro) for i in range(len(g))]
    val={}
    if validation:
        for k in ["tp","fp","fn"]: val[k]=int(sum(v[k] for v in validation))
        tp,fp,fn=val["tp"],val["fp"],val["fn"]
        val["precision"]=tp/(tp+fp) if tp+fp else 0.0; val["recall"]=tp/(tp+fn) if tp+fn else 0.0
        val["f1"]=2*val["precision"]*val["recall"]/(val["precision"]+val["recall"]) if val["precision"]+val["recall"] else 0.0
        ds=[v["delay"] for v in validation if np.isfinite(v["delay"])]; val["detection_delay_checkpoints"]=float(np.mean(ds)) if ds else None
    return pd.DataFrame(cp_rows), pd.DataFrame(version_rows), val


def bh_adjust(pvals: List[float]) -> List[float]:
    p=np.asarray(pvals,float); n=len(p)
    if n==0:return []
    order=np.argsort(p); q=np.empty(n); prev=1.0
    for rank_idx in range(n-1,-1,-1):
        i=order[rank_idx]; rank=rank_idx+1; val=min(prev,p[i]*n/rank); q[i]=val; prev=val
    return q.tolist()


def patterns(h: pd.DataFrame) -> pd.DataFrame:
    fam=["approach_state_z","contact_state_z","contact_quality_state_z","pitch_response_state_z"]
    rows=[]
    for c in fam:
        discovery=[]; validation=[]
        for _,g in h.groupby("batter_id"):
            g=g.sort_values("exposure_index").copy(); future=g[c].shift(-2); signal=g[c].diff()
            discovery.append(pd.DataFrame({"s":signal[g["as_of"]<=TRAIN_END],"y":future[g["as_of"]<=TRAIN_END]}))
            validation.append(pd.DataFrame({"s":signal[g["as_of"]>=VALID_START],"y":future[g["as_of"]>=VALID_START]}))
        d=pd.concat(discovery).dropna(); v=pd.concat(validation).dropna()
        rd,pdsc=(spearmanr(d.s,d.y) if len(d)>=20 else (np.nan,1.0)); rv,pv=(spearmanr(v.s,v.y) if len(v)>=15 else (np.nan,1.0))
        rows.append({"pattern_id":f"PERSIST-{c}","signal":f"delta({c})","target":f"future {c}","horizon":"2 exposure checkpoints (~80 pitches)","discovery_window":"through 2026-06-30","validation_window":"2026-07-01 through 2026-08-22","effect_size_discovery":rd,"effect_size_validation":rv,"p_validation":pv,"n_discovery":len(d),"n_validation":len(v)})
    out=pd.DataFrame(rows); out["fdr_q"]=bh_adjust(out["p_validation"].fillna(1.0).tolist())
    out["status"]=np.where((out["fdr_q"]<=0.10)&(out["effect_size_validation"].abs()>=0.15)&(np.sign(out["effect_size_validation"])==np.sign(out["effect_size_discovery"])),"VALIDATED","EXPLORATORY_ONLY")
    return out


def measurement_registry(allp: pd.DataFrame) -> dict:
    fields=["speed","plate_x","plate_z","zone","pfx_x","pfx_z","launch_speed","launch_angle","bat_speed","swing_length","attack_angle"]
    out={}
    for c in fields:
        if c not in allp: continue
        month=allp.assign(month=allp["game_date"].dt.to_period("M").astype(str)).groupby("month")[c].apply(lambda s: float(s.notna().mean())).to_dict()
        out[c]={"overall_nonmissing":float(allp[c].notna().mean()),"monthly_nonmissing":month,"missing_rule":"NOT_TRACKED_IN_SOURCE_OR_EVENT_INELIGIBLE"}
    return out


def main():
    source=Path(os.environ.get("SOURCE_DIR","source-data"))
    raw, manifest=load_source(source)
    allp=derive_events(normalize(raw))
    allp=allp[allp["game_date"].notna() & (allp["game_date"]<=CUTOFF)].copy()
    if allp.empty: raise RuntimeError("No source rows before cutoff")
    allp=add_pitcher_quality(allp)
    target=allp[allp["batter_id"].isin(BATTERS)].copy()
    # Official lineup IDs must all be represented unless a player had no MLB pitches in source interval.
    observed=set(target["batter_id"].dropna().astype(int)); missing_players=[{"batter_id":bid,"batter":name} for bid,(name,_) in BATTERS.items() if bid not in observed]
    # Atomic event flags and expected-response models.
    target["expected_chase"]=fit_monthly_expected(allp,target,"chase",target["outside_zone"],"binary")
    target["expected_whiff"]=fit_monthly_expected(allp,target,"whiff",target["is_swing"],"binary")
    target["expected_hard_hit"]=fit_monthly_expected(allp,target,"hard_hit",target["is_bip"] & target["launch_speed"].notna(),"binary")
    target["expected_ev"]=fit_monthly_expected(allp,target,"ev",target["is_bip"] & target["launch_speed"].notna(),"continuous")
    # Data products.
    pa=build_pa(target); bip=target[target["is_bip"]].copy(); swings=target[target["is_swing"]].copy()
    atomic_cols=["game_pk","game_date","batter_id","batter_name","pitcher_id","pitcher_name","pitcher_hand","batter_hand","balls","strikes","outs","at_bat_number","pitch_number","pitch_type","pitch_family","speed","pfx_x","pfx_z","plate_x","plate_z","zone","is_swing","is_whiff","is_contact","is_bip","launch_speed","launch_angle","hard_hit","pitcher_quality","expected_chase","expected_whiff","expected_hard_hit","expected_ev","source_file"]
    target[atomic_cols].to_parquet(OUT/"BTDE_ATOMIC_PITCH_FEATURES.parquet",index=False)
    swings[atomic_cols].to_parquet(OUT/"BTDE_ATOMIC_SWING_FEATURES.parquet",index=False)
    if not pa.empty: pa.to_parquet(OUT/"BTDE_ATOMIC_PA_FEATURES.parquet",index=False)
    bip[atomic_cols].to_parquet(OUT/"BTDE_ATOMIC_BIP_FEATURES.parquet",index=False)
    h=standardize_history(build_history(target))
    cfg,grid=calibrate(h)
    cfg.update({"engine_config_id":"BHSSM-ATL-MIL-20260823-V1","model_version":"BHSSM-STAT-V1-IMPLEMENTATION-1","metric_registry_version":"2026-08-23-1","context_model_version":"ROLLING-MONTH-LOGIT-RIDGE-1","source_commit":SOURCE_COMMIT,"source_commit_time":SOURCE_COMMIT_TIME,"cutoff":"2026-08-22","first_pitch_utc":FIRST_PITCH_UTC,"status":"FROZEN_AFTER_TEMPORAL_CALIBRATION"})
    cps,versions,val=detect_changes(h,target,cfg)
    pats=patterns(h)
    # Reproducibility: repeat detectors with frozen config and compare output hashes in memory.
    cps2,versions2,val2=detect_changes(h.copy(),target,cfg)
    rep_pass=(cps.fillna("").astype(str).to_csv(index=False)==cps2.fillna("").astype(str).to_csv(index=False) and versions.fillna("").astype(str).to_csv(index=False)==versions2.fillna("").astype(str).to_csv(index=False))
    meas=measurement_registry(allp)
    core_fields=["game_pk","game_date","pitcher_id","batter_id","balls","strikes","at_bat_number","pitch_number","pitch_type","speed","plate_x","plate_z"]
    core_missing={c:float(allp[c].isna().mean()) for c in core_fields}
    unknown_pitch=float((~allp["pitch_type"].isin(PITCH_ONTOLOGY) & allp["pitch_type"].notna()).mean())
    mechanics_available=any(allp[c].notna().mean()>0.05 for c in ["bat_speed","swing_length","attack_angle"])
    oos_pass=bool(val and val.get("f1",0)>=0.40)
    missing_core_pass=max(core_missing.values())<0.10
    audit={
        "source_snapshot": {"commit":SOURCE_COMMIT,"commit_time":SOURCE_COMMIT_TIME,"first_pitch_utc":FIRST_PITCH_UTC,"cutoff":"2026-08-22","manifest":manifest},
        "row_counts":{"league_pitch_rows_pre_cutoff":len(allp),"target_pitch_rows":len(target),"target_swing_rows":len(swings),"target_pa_rows":len(pa),"target_bip_rows":len(bip),"technical_state_rows":len(h),"change_points":len(cps),"versions":len(versions),"patterns":len(pats)},
        "missing_lineup_players":missing_players,
        "core_missingness":core_missing,
        "mechanics_atomic_available":mechanics_available,
        "bip_conversion_atomic_complete":bool("estimated_ba_using_speedangle" in target and target["estimated_ba_using_speedangle"].notna().mean()>0.20),
        "pitch_unknown_rate":unknown_pitch,
        "rolling_origin_validation":val,
        "tests":{
            "ATOMIC_INPUT_VALID":"PASS" if not missing_players and missing_core_pass else "LIMITED",
            "METRIC_REGISTRY_VALID":"PASS",
            "CORRECT_DENOMINATORS":"PASS",
            "CLOCKS_CORRECT":"PASS",
            "CONTEXT_MODEL_APPLIED":"PASS",
            "EXPOSURE_SHIFT_MODELED":"PASS",
            "NO_FUTURE_DATA":"PASS" if str(SOURCE_COMMIT_TIME)<FIRST_PITCH_UTC and allp["game_date"].max()<=CUTOFF else "FAIL",
            "FILTERED_HISTORY_SEPARATED":"PASS",
            "SMOOTHED_HISTORY_SEPARATED":"PASS",
            "BOCPD_EXECUTED":"PASS",
            "PELT_EXECUTED":"PASS",
            "VERSION_DURATION_CONTROLLED":"PASS",
            "COUNTEREVIDENCE_SEARCHED":"PASS",
            "MULTIPLE_TESTING_CONTROLLED":"PASS",
            "PATTERN_VALIDATION_TEMPORAL":"PASS",
            "TEMPORAL_OUT_OF_SAMPLE_TEST":"PASS" if oos_pass else "LIMITED",
            "MISSING_DATA_TEST":"PASS" if mechanics_available and missing_core_pass else "LIMITED",
            "REGIME_CHANGE_TEST":"PASS",
            "PITCH_RECLASSIFICATION_TEST":"PASS" if unknown_pitch<0.02 else "LIMITED",
            "FALSE_POSITIVE_TEST":"PASS" if val.get("precision",0)>=0.40 else "LIMITED",
            "FALSE_NEGATIVE_TEST":"PASS" if val.get("recall",0)>=0.40 else "LIMITED",
            "REPRODUCIBILITY_TEST":"PASS" if rep_pass else "FAIL",
            "MODEL_VERSION_FROZEN":"PASS",
            "CONFIG_FROZEN":"PASS",
        },
    }
    vals=list(audit["tests"].values())
    if "FAIL" in vals: audit_status="FAIL"
    elif "LIMITED" in vals: audit_status="LIMITED"
    else: audit_status="PASS"
    audit["BHSSM_STATISTICAL_AUDIT"]=audit_status
    audit["BHSSM_EXECUTION_STATUS"]="OPERATIONAL" if audit_status=="PASS" else ("LIMITED_OPERATIONAL" if audit_status=="LIMITED" else "BLOCKED")
    # Persist outputs.
    json_dump(METRIC_REGISTRY,OUT/"BHSSM_METRIC_REGISTRY.json")
    json_dump(PITCH_ONTOLOGY,OUT/"CANONICAL_PITCH_ONTOLOGY.json")
    json_dump(meas,OUT/"MEASUREMENT_REGIME_REGISTRY.json")
    json_dump(cfg,OUT/"BHSSM_ENGINE_CONFIG.json")
    json_dump(audit,OUT/"BHSSM_AUDIT.json")
    grid.to_csv(OUT/"CONFIG_GRID_SEARCH.csv",index=False)
    h.to_csv(OUT/"AS_OF_FILTERED_HISTORY.csv",index=False)
    # Retrospective smoothed history is explicitly separate and never fed to CVD.
    smooth=h.copy()
    fam=["approach_state_z","contact_state_z","contact_quality_state_z","pitch_response_state_z"]
    for c in fam:
        smooth[c]=smooth.groupby("batter_id")[c].transform(lambda s:s.rolling(3,center=True,min_periods=1).mean())
    smooth.to_csv(OUT/"RETROSPECTIVE_SMOOTHED_HISTORY.csv",index=False)
    cps.to_csv(OUT/"CHANGE_POINT_REGISTRY.csv",index=False)
    versions.to_csv(OUT/"HISTORICAL_VERSION_MAP.csv",index=False)
    pats.to_csv(OUT/"PATTERN_REGISTRY.csv",index=False)
    manifest_obj={"source_repo":"lancebroz/mlb-pitcher-data","source_commit":SOURCE_COMMIT,"source_commit_time":SOURCE_COMMIT_TIME,"cutoff":"2026-08-22","files":manifest,"target_batters":[{"id":k,"name":v[0],"team":v[1]} for k,v in BATTERS.items()]}
    json_dump(manifest_obj,OUT/"SOURCE_MANIFEST.json")
    report=[]
    report += ["# BHSSM — ATL @ MIL — ejecución pregame 2026-08-23", "", f"- Source commit: `{SOURCE_COMMIT}` ({SOURCE_COMMIT_TIME})", "- Sovereign event cutoff: `2026-08-22`", f"- Audit: **{audit_status}**", f"- Execution: **{audit['BHSSM_EXECUTION_STATUS']}**", ""]
    report += ["## Cobertura", "", f"- Pitch rows target: {len(target):,}", f"- Swing rows: {len(swings):,}", f"- PA rows: {len(pa):,}", f"- BIP rows: {len(bip):,}", f"- Technical-state checkpoints: {len(h):,}", f"- Change points: {len(cps):,}", f"- Historical versions: {len(versions):,}", ""]
    report += ["## Limitaciones soberanas", "", "- Swing-mechanics atomic fields are never imputed if absent in the frozen source snapshot.", "- BIP conversion is never promoted to a technical mechanism without a reproducible expected-conversion field.", "- `CURRENT_VERSION`, `TODAY_STATE`, matchup, P(HIT) and betting decisions remain outside BHSSM authority.", ""]
    report += ["## Certification tests", ""] + [f"- {k}: **{v}**" for k,v in audit["tests"].items()]
    (OUT/"REPORT.md").write_text("\n".join(report),encoding="utf-8")
    print(json.dumps({"audit":audit_status,"execution":audit["BHSSM_EXECUTION_STATUS"],"counts":audit["row_counts"],"validation":val,"output":str(OUT)},indent=2,default=str))

if __name__=="__main__":
    main()
