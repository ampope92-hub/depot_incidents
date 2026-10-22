# Depot Incidents: Allocating a Safety Programme from a Biased Incident Log in Free Pascal

A logistics network has a fixed number of places on this year's safety programme, and a memo recommends which depots should get them. The agent is asked to rebuild the list from the raw export instead: an incident log, the insurer's claims file, a depot register with hours worked, a pilot-year file, a policy JSON and a README. It must write a Free Pascal program that writes a JSON object `{"depots": [...]}` with exactly `list_size` depot ids, no merged depots and no repeats. The same binary is then run on two other networks' exports.

## What makes it hard

The memo's league table is arithmetically correct but measures the wrong thing. It ranks logged incidents per hour, and minor incidents are logged at whatever rate each depot bothers to log them (from almost never to almost always). Only severe incidents are complete, because every severe one is entered by the regional lead and carries an insurer claim. So the memo ranks paperwork as much as risk. Getting the list right takes several separate readings of the export, and each one fails on its own:

- **Severe vs. logged rate.** The memo's thirty score 1.390 against a bar of 1.65 on the shipped (Southern) network. Ranking by severe incidents per hour scores 1.970. Weighting the rate by budgeted hours (expected count rather than rate) gets 1.421 / 1.378 and misses.
- **Site vs. depot column.** The log files an incident under the injured person's home depot, while the `site` column says where it happened. At hubs these diverge sharply. Using the depot column passes the shipped network (1.939) but gets 1.429 on the Northern network, where twenty hubs are mostly staffed by trunk drivers from other depots. The insurer's claims file carries the same bias.
- **Hours.** A depot's hours are payroll plus agency columns. Payroll alone passes the shipped network (1.975) but misses the Northern network (1.625 vs 1.70), where thirty depots run mostly on agency staff.
- **Merged depots.** Merged depots keep their hours on their own rows while their incidents move to the survivor. Each register has a merger chain (11 / 8 / 7 rows) that must be followed to the id left standing. Treating rows independently gives 1.545 / 1.381 / 1.404, and following a single hop gives 1.566 / 1.502 / 1.541. Both miss every bar.
- **Nothing transfers between networks.** The three exports differ in depot count (180 / 150 / 260), list size (30 / 20 / 50), bar (1.65 / 1.70 / 1.62), log years, id format (`WST-` ids of 7-9 characters on the Western network), and policy JSON layout (minified, reordered keys, escaped strings).

The program itself is small: two CSV reads, a per-depot tally, a division and a partial sort, with hand-written JSON output. Thresholds were calibrated across twelve generated networks per shape with `solution/calibrate.py`.

## How it's graded

The verifier runs in a separate, offline container. It compiles `src/` itself with fpc as an unprivileged user (the agent's `build.sh` is not run). It inspects the link script fpc generates and refuses the link if it names any input fpc did not produce. The binary then runs on three exports (Southern shipped, plus Northern and Western, staged read-only only after the build). Seven checks:

- all six shipped files unaltered (sha256)
- per run: exactly one key `depots` (duplicate keys rejected), exactly `list_size` valid, non-merged, distinct ids
- per run: the incident rate at the listed depots in the programme year (payroll plus agency hours, merger chains fully resolved) is at least `minimum_rate_ratio` times the network rate. The key is per-depot counts from the programme year, which the binary never sees.

Sandboxing: all system executables (including `env`) are closed to the build user. Project files have their execute bits stripped. There is no writable directory, and the output is a pre-created root-owned file. A seccomp launcher (`tests/launch.c`) refuses fork, clone and `memfd_create`. Process groups are swept after each run, and pytest runs with `-P`. `task.toml` documents 28 wrong or cheating arms scoring 0, including linked foreign objects, embedded ELF helpers, fork workers, frozen lists and dispatching on policy values. Several legitimate variants (multi-file Pascal projects, reversed output order) score 1.

## Repository layout

- `instruction.md` - the task prompt given to the agent
- `task.toml` - metadata, limits, and the difficulty, solution and verification write-ups
- `environment/` - agent container: `Dockerfile`, `data/` (incident log, insurer claims, depot register, pilot year, policy, README), `watch/` (stub `src/watch.pas` and `build.sh`)
- `solution/` - `solve.sh`, reference `watch.pas`, `gen_incidents.py` (regenerates all three exports and keys byte for byte), `calibrate.py` (reproduces the route figures)
- `tests/` - verifier `Dockerfile`, `test.sh`, `test_outputs.py`, seccomp `launch.c`, and keys/data for the Southern (`golden/`), Northern (`hidden/`) and Western (`third/`) networks

## Running it

Requires Docker and Harbor (`uv tool install harbor` or `pip install harbor`). From the repo root:

```
harbor run -p . -a oracle
```

runs the reference solution through the verifier (should score reward 1). To try an agent:

```
harbor run -p . -a <agent> -m <model>
```

for example `-a claude-code`.

---

Task design, data generators, reference solution and verifier by Audrey Pope.
