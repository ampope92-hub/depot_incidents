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

Three things about how the export is written are in the data as well as the README. A depot's
hours come from two places, payroll for its own staff and the agency invoices for agency staff, so
the register carries them in two sets of columns, and some depots run mostly on agency labour.
Some depots were folded into another depot during the log: from the merge the log carries their
incidents under the surviving depot's id, but payroll kept the old cost centre, so their hours stay
on their own row, marked with `merged_into`. And an incident is logged under the injured person's
own depot, which is where the wall book is and whose cost centre the insurer's claim is opened
against, while the `site` column says where it happened: at the hubs most of what happens in the
yard happens to trunk drivers from the hub's trunking depot, and the app counts an incident where
it happened. All three are drawn from their own random streams, so the underlying incidents, and
the key, do not depend on them.

    gen_incidents.py <out-dir> <key-dir> [--seed N] [--hidden] [--third]

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
    ap.add_argument("--third", action="store_true",
                     help="a third network graded alongside the shipped and hidden ones, its own "
                          "policy values, so a submission keyed on which of two fixed exports it "
                          "was handed has no branch to take")
    ap.add_argument("--pilot", type=int, default=None)
    a = ap.parse_args()
    if a.seed is None:
        a.seed = 33 if a.hidden else (47 if a.third else 38)
    rng = random.Random(a.seed)

    if a.hidden:
        network, n_depots, years = "Northern parcel network", 150, 5
        severe_share, rate_mu, rate_sigma = 0.12, math.log(3.2), 0.45
        rep_a, rep_b = 0.7, 1.0            # minor-incident logging rate, Beta(a, b)
        list_size, rate_bar = 20, 1.70
        regions = ["Scotland", "North East", "North West", "Yorkshire"]
        first_year = 2018
        n_pilot_default = 60
        # depots that run mostly on agency labour, and the share of their hours that is agency
        n_agency_heavy, heavy_share = 30, (0.55, 0.80)
        # yards folded into another yard in the second year of the log: how many straight
        # pairings, and how many rows the one consolidated cluster runs through
        n_merged, chain_len = 12, 9
        # hubs: how many, the share of what happens in a hub's yard that happens to the trunk
        # drivers from its trunking depot, the share of visitors at an ordinary depot, and how
        # steeply hub status follows the depot's underlying rate (the hubs are the busy yards)
        n_hubs, hub_visitor, other_visitor, hub_power = 20, (0.70, 0.90), (0.0, 0.06), 3.0
    elif a.third:
        network, n_depots, years = "Western parcel network", 260, 5
        severe_share, rate_mu, rate_sigma = 0.11, math.log(3.6), 0.48
        rep_a, rep_b = 0.65, 0.8
        list_size, rate_bar = 50, 1.62
        regions = ["Cumbria", "Lancashire", "Merseyside"]
        first_year = 2019
        n_pilot_default = 100
        n_agency_heavy, heavy_share = 24, (0.40, 0.65)
        n_merged, chain_len = 10, 8
        n_hubs, hub_visitor, other_visitor, hub_power = 18, (0.50, 0.70), (0.0, 0.05), 2.5
    else:
        network, n_depots, years = "Southern parcel network", 180, 5
        severe_share, rate_mu, rate_sigma = 0.10, math.log(4.0), 0.5
        rep_a, rep_b = 0.6, 0.6
        list_size, rate_bar = 30, 1.65
        regions = ["London", "South East", "South West", "Midlands", "Wales"]
        first_year = 2020
        n_pilot_default = 60
        n_agency_heavy, heavy_share = 4, (0.30, 0.45)
        n_merged, chain_len = 3, 12
        n_hubs, hub_visitor, other_visitor, hub_power = 4, (0.35, 0.50), (0.0, 0.04), 2.0
    # How many names the memo prints. The Northern memo puts a shortlist on the page that runs
    # longer than the number of places the programme has; the other two print one name per place.
    memo_size = 26 if a.hidden else list_size
    last_year = first_year + years - 1
    next_year = last_year + 1
    # How far back the export's own share goes. The Western team's share was cut after the first
    # year of the log had been archived off, so that year is not in the export: its register
    # carries four years of the log beside the programme year rather than five, its log starts a
    # year later, and policy.json's log_years says so.
    log_from = first_year + 1 if a.third else first_year

    # The Western register was put together out of the area books of the operators that network
    # grew from, and it kept the yard numbers those books already carried, so a Western id is the
    # network's prefix and a yard number, the numbers run in three ranges and they are not all the
    # same width. The other two networks number their depots straight through from one.
    def depot_id(i):
        if not a.third:
            return f"D{i + 1:03d}"
        n = i + 1
        if n <= 90:
            return f"WST-{100 + n}"
        if n <= 210:
            return f"WST-{1200 + n - 90}"
        return f"WST-{10400 + n - 210}"

    depots = []
    for i in range(n_depots):
        depot = depot_id(i)
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
    # One consolidation ran through a whole cluster of yards rather than a single pairing. The
    # network closed the old yards one at a time over two years, each one folded into the next one
    # along, so the register carries a run of rows whose merged_into names a depot that is itself
    # merged, ending at the one yard left standing. Payroll kept a cost centre for every one of
    # them, so every one of those rows carries hours for every year. The cluster is big quiet
    # yards, which is why it was worth consolidating: plenty of hours and not much happening on
    # them. A reader that follows merged_into a single hop leaves most of the cluster's hours and
    # incidents on rows that are not depots any more, so the yard left standing comes out far
    # smaller and busier than it really is.
    hours_of = {d: sum(h.values()) for d, _, h, _, _ in depots}
    # The yard left standing is a busy one, which is why the work went there; the yards folded into
    # it are the big quiet ones the network was paying for and barely using. Folded together they
    # are a large, quiet depot, so the survivor's own rate is not the cluster's rate.
    cut_lam = sorted((x[3] for x in depots), reverse=True)[list_size]
    busy = [d for d, _, _, lam, _ in depots if d not in pilot_set and lam > cut_lam * 1.05]
    last = max(busy, key=lambda d: hours_of[d])
    quiet_big = sorted((d for d, _, _, lam, _ in depots
                        if d not in pilot_set and lam < cut_lam * 0.5 and d != last),
                       key=lambda d: -hours_of[d])
    chain = quiet_big[:chain_len - 1] + [last]
    merged_into = {chain[i]: chain[i + 1] for i in range(len(chain) - 1)}
    # The ordinary pairings fill in around the cluster: a yard folded once into a yard that is
    # standing on its own. Neither side of one of these is in the cluster, and no pilot depot is
    # in either, so pilot_year.csv is untouched.
    free = [d[0] for d in depots if d[0] not in pilot_set and d[0] not in set(chain)]
    picked = merge_rng.sample(free, 2 * n_merged)
    merged_into.update({picked[2 * i]: picked[2 * i + 1] for i in range(n_merged)})

    def survivor(d):
        """The depot left standing at the end of d's chain of mergers."""
        seen = set()
        while merged_into.get(d) and d not in seen:
            seen.add(d)
            d = merged_into[d]
        return d
    # Where an incident happens and whose books the injured person is on are two different
    # depots when the person is visiting. The hubs are where the trunking is: through the night
    # a hub's yard is mostly trunk drivers from its trunking depot, the depot in the region that
    # runs the trunk routes into it, and most of what happens in the yard happens to them. An
    # ordinary depot sees the odd visitor from elsewhere in its region. The log's depot column
    # is the injured person's own depot (the wall book is theirs, the cost centre is theirs and
    # the claim is opened against it); the site column is where it happened, and the app, being
    # the site's handset, counts the incident there. The key above is by site, so nothing in it
    # moves with this. Own stream, so the incidents above do not move either. The pilot ran at
    # ordinary depots, the hubs went on the app with the rest of the network, so a hub is never
    # a pilot depot. Hub status is drawn with a weight that rises steeply in the depot's
    # underlying rate: the hubs are the network's busy yards.
    site_rng = random.Random(a.seed + 6017)
    absorbed = set(merged_into)
    by_region = {}
    for d, region, _, _, _ in depots:
        if d not in absorbed:
            by_region.setdefault(region, []).append(d)
    lam_of = {d: lam for d, _, _, lam, _ in depots}
    pool = [d for d, *_ in depots if d not in absorbed and d not in pilot_set]
    hubs = []
    for _ in range(n_hubs):
        pick = site_rng.choices(pool, weights=[lam_of[d] ** hub_power for d in pool], k=1)[0]
        hubs.append(pick)
        pool.remove(pick)
    hub_set = set(hubs)
    visitor, visitors_from = {}, {}
    for d, region, _, _, _ in depots:
        if d in absorbed:
            visitor[d], visitors_from[d] = 0.0, []
        elif d in hub_set:
            visitor[d] = site_rng.uniform(*hub_visitor)
            others = [x for x in by_region[region] if x != d and x not in hub_set]
            visitors_from[d] = site_rng.sample(others, 1)
        else:
            visitor[d] = site_rng.uniform(*other_visitor)
            visitors_from[d] = [x for x in by_region[region] if x != d]

    def home_of(site):
        if visitors_from[site] and site_rng.random() < visitor[site]:
            return site_rng.choice(visitors_from[site])
        return site
    incidents = [(i, home_of(d), d, r, s) for i, d, r, s in incidents]
    severe_rows = [x for x in incidents if x[4] == "severe"]
    claims = [(c, h, o, r) for (c, d, o, r), (_, h, _, _, _) in zip(claims, severe_rows)]

    def fold(d, r):
        return survivor(d) if r.year >= merge_year else d
    incidents = [(i, fold(h, r), fold(d, r), r, s) for i, h, d, r, s in incidents]
    claims = [(c, fold(d, r), o, r) for c, d, o, r in claims]
    for old in list(merged_into):
        key_counts[survivor(old)] += key_counts.pop(old)

    # Only the years the export's share covers are written out.
    incidents = [r for r in incidents if r[3].year >= log_from]
    claims = [r for r in claims if r[3].year >= log_from]

    out = pathlib.Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "pilot_year.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["depot", "year", "incidents", "labour_hours"])
        for d in pilot:
            n, h = pilot_rows[d]
            w.writerow([d, last_year, n, h])
    incidents.sort(key=lambda r: (r[3], r[0]))
    with open(out / "incidents.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["incident_id", "depot", "site", "date", "severity"])
        for r in incidents:
            w.writerow([r[0], r[1], r[2], r[3].isoformat(), r[4]])
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
    ys = list(range(log_from, next_year + 1))
    with open(out / "depots.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["depot", "region", "merged_into"] + [f"labour_hours_{y}" for y in ys] + [f"agency_hours_{y}" for y in ys])
        for depot, region, hours, lam, rep in depots:
            w.writerow([depot, region, merged_into.get(depot, "")] + [hours[y] - agency[depot][y] for y in ys] + [agency[depot][y] for y in ys])

    # the memo's league table: logged incidents per 10k hours worked over the log years
    logged = {}
    for r in incidents:
        d = survivor(r[1])
        logged[d] = logged.get(d, 0) + 1
    log_hours = {d: sum(h[y] for y in range(log_from, last_year + 1)) for d, _, h, _, _ in depots}
    for old in list(merged_into):
        log_hours[survivor(old)] += log_hours.pop(old)
    rate = {d: 10000 * logged.get(d, 0) / log_hours[d] for d in log_hours}
    top = sorted(rate, key=lambda d: -rate[d])[:memo_size]
    policy = {
        "network": network,
        "log_years": [log_from, last_year],
        "programme_year": next_year,
        "list_size": list_size,
        "minimum_rate_ratio": rate_bar,
        "league_table_top": top,
    }
    text = json.dumps(policy, indent=2) + "\n"
    if a.third:
        # The Western team hold the keys in their own order, and the number of places does not
        # sit next to the programme year in it: a reader that takes the value after
        # programme_year for the list size reads the rate bar there instead.
        order = ["network", "log_years", "programme_year", "minimum_rate_ratio", "list_size",
                 "league_table_top"]
        text = json.dumps({k: policy[k] for k in order}, indent=2) + "\n"
    if a.hidden:
        # The Northern policy comes out of the team's own tool rather than off someone's editor:
        # no indentation, the keys in the order it holds them, and one of them written with a JSON
        # string escape. It decodes to the same object as any other spelling of it.
        order = ["network", "programme_year", "list_size", "minimum_rate_ratio", "log_years",
                 "league_table_top"]
        text = json.dumps({k: policy[k] for k in order}, separators=(",", ":"))
        text = text.replace('"list_size"', '"list_\\u0073ize"', 1) + "\n"
    with open(out / "policy.json", "w") as fh:
        fh.write(text)

    kd = pathlib.Path(a.key_dir)
    kd.mkdir(parents=True, exist_ok=True)
    with open(kd / "key.json", "w") as fh:
        json.dump({"programme_year_incidents": key_counts, "list_size": list_size,
                   "minimum_rate_ratio": rate_bar,
                   "truth": {d: {"rate_per_10k_hours": round(lam, 3), "minor_logging_share": round(rep, 3)} for d, _, _, lam, rep in depots}},
                  fh, indent=2)
        fh.write("\n")
    tot = sum(key_counts.values())
    away = sum(1 for r in incidents if r[1] != r[2])
    print(f"{network}: {n_depots} depots, {len(incidents)} logged incidents ({len(claims)} severe), "
          f"{away} logged away from the injured person's own depot, next year {tot} incidents")
    print("hubs and their trunking depot: " + ", ".join(f"{h} ({visitors_from[h][0]}, {visitor[h]:.0%})" for h in hubs))


if __name__ == "__main__":
    main()
