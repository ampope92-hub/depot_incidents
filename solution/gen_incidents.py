#!/usr/bin/env python3
"""Generate a depot network's incident log, the insurer's claims file, the depot register, the
policy, and the key.

Each depot has its own underlying incident rate per hour worked, and it does not move from year
to year. A small fixed share of incidents are severe: those are always logged, and the insurer
opens a claim on every one. Minor incidents are logged only as often as that depot's staff bother
to log them, and depots differ a lot in that. A pilot ran the app alongside the book for one year
at sixty depots, and what the app counted for each of them is published, so the gap between the
book and the truth is on the page. The key holds next year's incident count per depot, once every
depot logs every incident.

Two things about how the export is written are in the data as well as the README. A depot's hours
come from two places, payroll for its own staff and the agency invoices for agency staff, so the
register carries them in two sets of columns, and some depots run mostly on agency labour. And
some depots were folded into another depot during the log: from the merge the log carries their
incidents under the surviving depot's id, but payroll kept the old cost centre, so their hours stay
on their own row, marked with `merged_into`. Both are drawn from their own random streams, so the
underlying incidents do not depend on them.

    gen_incidents.py <out-dir> <key-dir> [--seed N] [--hidden]

Standard library only.
"""
import argparse
import csv
import datetime as dt
import json
import math
import pathlib
import random


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("key_dir")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--hidden", action="store_true")
    ap.add_argument("--pilot", type=int, default=None)
    a = ap.parse_args()
    if a.seed is None:
        a.seed = 33 if a.hidden else 38
    rng = random.Random(a.seed)

    if a.hidden:
        network, n_depots, years = "Northern parcel network", 150, 5
        severe_share, rate_mu, rate_sigma = 0.12, math.log(3.2), 0.45
        rep_a, rep_b = 0.7, 1.0            # minor-incident logging rate, Beta(a, b)
        list_size, rate_bar = 20, 1.60
        regions = ["Scotland", "North East", "North West", "Yorkshire"]
        first_year = 2018
        n_pilot_default = 60
        # depots that run mostly on agency labour, and the share of their hours that is agency
        n_agency_heavy, heavy_share = 30, (0.55, 0.80)
        # depots folded into another depot in the second year of the log
        n_merged = 15
    else:
        network, n_depots, years = "Southern parcel network", 180, 5
        severe_share, rate_mu, rate_sigma = 0.10, math.log(4.0), 0.5
        rep_a, rep_b = 0.6, 0.6
        list_size, rate_bar = 30, 1.65
        regions = ["London", "South East", "South West", "Midlands", "Wales"]
        first_year = 2020
        n_pilot_default = 60
        n_agency_heavy, heavy_share = 4, (0.30, 0.45)
        n_merged = 2
    last_year = first_year + years - 1
    next_year = last_year + 1

    depots = []
    for i in range(n_depots):
        depot = f"D{i + 1:03d}"
        hours = {y: int(rng.lognormvariate(math.log(260000), 0.3)) for y in range(first_year, next_year + 1)}
        lam = rng.lognormvariate(rate_mu, rate_sigma)            # incidents per 10k labour hours
        rep = rng.betavariate(rep_a, rep_b)                       # share of minor incidents that get logged
        depots.append((depot, rng.choice(regions), hours, lam, rep))

    incidents, claims = [], []
    key_counts = {}
    # A pilot ran the app alongside the wall book at a slice of the network for one year. The log
    # keeps its usual habit for those depots; the app counted everything. So for that year the same
    # depots appear twice, once as what got written down and once as what actually happened.
    pilot_rng = random.Random(a.seed + 4231)
    n_pilot = a.pilot if a.pilot else n_pilot_default
    pilot = sorted(pilot_rng.sample([d[0] for d in depots], min(n_pilot, len(depots))))
    pilot_set = set(pilot)
    pilot_rows = {}
    iid = cid = 0
    for depot, region, hours, lam, rep in depots:
        for y in range(first_year, next_year + 1):
            n = 0
            expected = lam * hours[y] / 10000
            # Poisson draw
            L, k, p = math.exp(-expected), 0, 1.0
            while True:
                p *= rng.random()
                if p <= L:
                    break
                k += 1
            n = k
            if y == next_year:
                key_counts[depot] = n
                continue
            on_app = depot in pilot_set and y == last_year
            if on_app:
                pilot_rows[depot] = (n, hours[y])
            for _ in range(n):
                day = dt.date(y, 1, 1) + dt.timedelta(days=rng.randint(0, 364))
                severe = rng.random() < severe_share
                if severe:
                    iid += 1
                    incidents.append((f"I{iid:06d}", depot, day, "severe"))
                    cid += 1
                    claims.append((f"C{cid:06d}", depot, day + dt.timedelta(days=rng.randint(3, 40)), day))
                elif rng.random() < rep:
                    iid += 1
                    incidents.append((f"I{iid:06d}", depot, day, "minor"))

    # Mergers. In the second year of the log some depots were folded into another depot. From the
    # merge the log carries the absorbed site's incidents under the survivor's id, and so does the
    # programme year, but payroll kept the old cost centre, so the absorbed depot's hours stay on
    # its own row, marked with merged_into. Neither side of a merger is a pilot depot, so
    # pilot_year.csv is untouched. Own stream, so nothing above moves with it.
    merge_rng = random.Random(a.seed + 7305)
    merge_year = first_year + 1
    free = [d[0] for d in depots if d[0] not in pilot_set]
    picked = merge_rng.sample(free, 2 * n_merged)
    merged_into = {picked[2 * i]: picked[2 * i + 1] for i in range(n_merged)}
    incidents = [(i, merged_into.get(d, d) if r.year >= merge_year else d, r, s) for i, d, r, s in incidents]
    claims = [(c, merged_into.get(d, d) if r.year >= merge_year else d, o, r) for c, d, o, r in claims]
    for old, new in merged_into.items():
        key_counts[new] += key_counts.pop(old)

    out = pathlib.Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "pilot_year.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["depot", "year", "incidents", "labour_hours"])
        for d in pilot:
            n, h = pilot_rows[d]
            w.writerow([d, last_year, n, h])
    incidents.sort(key=lambda r: (r[2], r[0]))
    with open(out / "incidents.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["incident_id", "depot", "date", "severity"])
        for r in incidents:
            w.writerow([r[0], r[1], r[2].isoformat(), r[3]])
    claims.sort(key=lambda r: (r[2], r[0]))
    with open(out / "insurer_claims.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["claim_id", "depot", "claim_opened", "incident_date"])
        for r in claims:
            w.writerow([r[0], r[1], r[2].isoformat(), r[3].isoformat()])
    # The hours a depot works are split between payroll (its own staff) and the agencies. The
    # split has its own stream so the incidents above do not move with it.
    agency_rng = random.Random(a.seed + 5160)
    heavy = set(agency_rng.sample([d[0] for d in depots], n_agency_heavy))
    agency = {}
    for depot, region, hours, lam, rep in depots:
        share = agency_rng.uniform(*heavy_share) if depot in heavy else agency_rng.uniform(0.0, 0.2)
        agency[depot] = {y: int(hours[y] * min(0.9, share * agency_rng.uniform(0.85, 1.15))) for y in hours}
    ys = list(range(first_year, next_year + 1))
    with open(out / "depots.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["depot", "region", "merged_into"] + [f"labour_hours_{y}" for y in ys] + [f"agency_hours_{y}" for y in ys])
        for depot, region, hours, lam, rep in depots:
            w.writerow([depot, region, merged_into.get(depot, "")] + [hours[y] - agency[depot][y] for y in ys] + [agency[depot][y] for y in ys])

    # the memo's league table: logged incidents per 10k hours worked over the log years
    logged = {}
    for r in incidents:
        d = merged_into.get(r[1], r[1])
        logged[d] = logged.get(d, 0) + 1
    log_hours = {d: sum(h[y] for y in range(first_year, last_year + 1)) for d, _, h, _, _ in depots}
    for old, new in merged_into.items():
        log_hours[new] += log_hours.pop(old)
    rate = {d: 10000 * logged.get(d, 0) / log_hours[d] for d in log_hours}
    top = sorted(rate, key=lambda d: -rate[d])[:list_size]
    policy = {
        "network": network,
        "log_years": [first_year, last_year],
        "programme_year": next_year,
        "list_size": list_size,
        "minimum_rate_ratio": rate_bar,
        "league_table_top": top,
    }
    with open(out / "policy.json", "w") as fh:
        json.dump(policy, fh, indent=2)
        fh.write("\n")

    kd = pathlib.Path(a.key_dir)
    kd.mkdir(parents=True, exist_ok=True)
    with open(kd / "key.json", "w") as fh:
        json.dump({"programme_year_incidents": key_counts, "list_size": list_size,
                   "minimum_rate_ratio": rate_bar,
                   "truth": {d: {"rate_per_10k_hours": round(lam, 3), "minor_logging_share": round(rep, 3)} for d, _, _, lam, rep in depots}},
                  fh, indent=2)
        fh.write("\n")
    tot = sum(key_counts.values())
    print(f"{network}: {n_depots} depots, {len(incidents)} logged incidents ({len(claims)} severe), "
          f"next year {tot} incidents")


if __name__ == "__main__":
    main()
