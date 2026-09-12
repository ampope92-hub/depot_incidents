#!/usr/bin/env python3
"""Where the bar sits, measured rather than chosen.

Generates networks with gen_incidents.py across seeds and scores, on each, the lists the likely
routes produce against the programme year's complete log: the memo's league table (every logged
incident per hour worked); the same by raw count; the league rate times the programme year's
budgeted hours, i.e. the memo's expected count; the reference (severe incidents per hour worked,
payroll and agency hours summed, a merged depot's row folded into its survivor); the insurer's
claims per hour, which is the same thing from the other file; the severe rate times budgeted
hours; the generator's own rates; and the two careless readings of the register, the hours taken
from the payroll columns alone (payroll_hours) and every row ranked as its own depot with
merged_into ignored (rows_apart). The figure printed for each is the listed depots' incidents per
hour over the programme year divided by the network's. A list that names a merged id is a miss
whatever its ratio, since the verifier rejects the id.

    calibrate.py [--seeds N]
"""
import argparse
import csv
import json
import pathlib
import statistics as st
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent


def routes(d, key):
    with open(d / "policy.json") as fh:
        pol = json.load(fh)
    y0, y1 = pol["log_years"]
    with open(d / "depots.csv", newline="") as fh:
        rows = {r["depot"]: r for r in csv.DictReader(fh)}
    into = {k: r["merged_into"] for k, r in rows.items() if r["merged_into"]}
    kept = [k for k in rows if k not in into]
    worked = lambda r, y: int(r[f"labour_hours_{y}"]) + int(r[f"agency_hours_{y}"])
    # per row, as the register stands
    row_hours = {k: sum(worked(r, y) for y in range(y0, y1 + 1)) for k, r in rows.items()}
    row_payroll = {k: sum(int(r[f"labour_hours_{y}"]) for y in range(y0, y1 + 1)) for k, r in rows.items()}
    row_next = {k: worked(r, pol["programme_year"]) for k, r in rows.items()}
    row_logged, row_severe, row_claims = ({k: 0 for k in rows} for _ in range(3))
    with open(d / "incidents.csv", newline="") as fh:
        for r in csv.DictReader(fh):
            row_logged[r["depot"]] += 1
            if r["severity"] == "severe":
                row_severe[r["depot"]] += 1
    with open(d / "insurer_claims.csv", newline="") as fh:
        for r in csv.DictReader(fh):
            row_claims[r["depot"]] += 1
    # per depot, merged rows folded into their survivor: what the verifier scores against
    hours, payroll, nh, logged, severe, claims, lam_h = ({k: v[k] for k in kept} for v in
        (row_hours, row_payroll, row_next, row_logged, row_severe, row_claims,
         {k: key["truth"][k]["rate_per_10k_hours"] * row_hours[k] for k in rows}))
    for a, b in into.items():
        hours[b] += row_hours[a]
        payroll[b] += row_payroll[a]
        nh[b] += row_next[a]
        logged[b] += row_logged[a]
        severe[b] += row_severe[a]
        claims[b] += row_claims[a]
        lam_h[b] += key["truth"][a]["rate_per_10k_hours"] * row_hours[a]
    return {
        "league_table_rate": {k: logged[k] / hours[k] for k in kept},
        "league_table_count": {k: logged[k] for k in kept},
        "league_rate_x_hours": {k: logged[k] / hours[k] * nh[k] for k in kept},
        "reference_severe_rate": {k: severe[k] / hours[k] for k in kept},
        "insurer_claims_rate": {k: claims[k] / hours[k] for k in kept},
        "severe_rate_x_hours": {k: severe[k] / hours[k] * nh[k] for k in kept},
        "generator_truth": {k: lam_h[k] / hours[k] for k in kept},
        "payroll_hours": {k: severe[k] / payroll[k] for k in kept},
        "rows_apart": {k: row_severe[k] / row_hours[k] for k in rows},
    }, pol, nh, set(into)


def ratio(scores, counts, nh, size, merged):
    top = sorted(scores, key=lambda k: (-scores[k], k))[:size]
    named = [k for k in top if k in merged]
    top = [k for k in top if k not in merged]
    listed = sum(counts[k] for k in top) / sum(nh[k] for k in top)
    return listed / (sum(counts.values()) / sum(nh.values())), len(named)


def score(d, key):
    sc, pol, nh, merged = routes(d, key)
    out = {}
    for name, s in sc.items():
        r, named = ratio(s, key["programme_year_incidents"], nh, pol["list_size"], merged)
        out[name] = (r, r >= pol["minimum_rate_ratio"] and named == 0, named)
    return out, pol


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=12)
    a = ap.parse_args()
    fmt = lambda v: f"{st.mean(v):6.3f} [{min(v):6.3f},{max(v):6.3f}]"
    for label, extra in [("Southern network, 30 places, bar 1.65", []),
                         ("Northern network, 20 places, bar 1.60", ["--hidden"])]:
        # the pinned export first: the one that ships, or the one the verifier holds
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp)
            subprocess.run([sys.executable, str(HERE / "gen_incidents.py"), str(d / "data"), str(d)] + extra,
                           check=True, capture_output=True)
            with open(d / "key.json") as fh:
                key = json.load(fh)
            out, _ = score(d / "data", key)
            print(f"== {label}, the pinned export")
            for name, (r, ok, named) in out.items():
                note = f", names {named} merged id(s)" if named else ""
                print(f"   {name:22s} rate ratio {r:6.3f}   {'clears' if ok else 'misses'} the bar{note}")
        res = {}
        with tempfile.TemporaryDirectory() as tmp:
            for seed in range(a.seeds):
                d = pathlib.Path(tmp) / f"s{seed}"
                subprocess.run([sys.executable, str(HERE / "gen_incidents.py"), str(d / "data"), str(d), "--seed", str(seed)] + extra,
                               check=True, capture_output=True)
                with open(d / "key.json") as fh:
                    key = json.load(fh)
                out, _ = score(d / "data", key)
                for name, v in out.items():
                    res.setdefault(name, []).append(v)
        print(f"== {label}, {a.seeds} seeds")
        for name, v in res.items():
            c = list(zip(*v))
            print(f"   {name:22s} rate ratio {fmt(c[0])}   clears the bar {sum(c[1])}/{len(c[1])}")


if __name__ == "__main__":
    main()
