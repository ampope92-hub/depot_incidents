"""Verifier for the programme list.

test.sh compiles the agent's Pascal itself, runs the binary once on the export that shipped,
twice more on other networks' exports it has never seen, and once more on the shipped export with
its policy.json serialised another way, and captures each depots.json root-only.
This module only reads those captures and the keys under /opt: what every depot logged in the
programme year once logging was mandatory. It never runs agent code.

Every bar here is stated in instruction.md, and the same bar applies to every run.
"""
import csv
import hashlib
import json
import os
import pathlib

import pytest

SHIPPED_RUN = pathlib.Path("/opt/run_shipped.json")
HIDDEN_RUN = pathlib.Path("/opt/run_hidden.json")
THIRD_RUN = pathlib.Path("/opt/run_third.json")
PROBE_RUN = pathlib.Path("/opt/run_probe.json")
SHIPPED_KEY = pathlib.Path("/opt/golden/key.json")
HIDDEN_KEY = pathlib.Path("/opt/hidden/key.json")
THIRD_KEY = pathlib.Path("/opt/third/key.json")
SHIPPED_DATA = pathlib.Path("/app/data")
HIDDEN_DATA = pathlib.Path("/opt/hidden/data")
THIRD_DATA = pathlib.Path("/opt/third/data")
# The shipped export with its policy re-serialised (tests/probe/policy.json), assembled by test.sh.
PROBE_DATA = pathlib.Path("/opt/probe_data")

SHIPPED_SHA = {
    "incidents.csv": "6c23c5877fdbb16d4d27de2f5ef58eed37f6d896d37479fea6c3eb1c02a993f8",
    "insurer_claims.csv": "56ac324f9db0d3a4b05369a0874f232ccd755b0d781e62b4363a55e308148ca7",
    "depots.csv": "eefb81f27572489e609608dc3f249de251a81d019f85352a8dfa11eba7ce0f2d",
    "policy.json": "3dffa501ed0779f6c616ab435c7f7a140e961f215f712e959cf1a783918c71e4",
    "pilot_year.csv": "066fb5a26d0fb2b1bd3151b84d9731b8cc206f762d2ccc33105f0c71cd9f951d",
    # README.md is hashed too: it is readable and its execute bit alone is stripped, and
    # dlopen()/mmap(PROT_EXEC) need only the read bit, so an unhashed README could carry a
    # dynamically loaded payload without tripping any other check. Pinning it closes that off
    # the same way the other five files are closed: any change to it fails this test.
    "README.md": "b9fc81a68068ff97f072a5602ef3643ecde9c088b185c915324465364677c612",
}

RUNS = [
    pytest.param(SHIPPED_RUN, SHIPPED_KEY, SHIPPED_DATA, id="shipped"),
    pytest.param(HIDDEN_RUN, HIDDEN_KEY, HIDDEN_DATA, id="hidden"),
    pytest.param(THIRD_RUN, THIRD_KEY, THIRD_DATA, id="third"),
    pytest.param(PROBE_RUN, SHIPPED_KEY, PROBE_DATA, id="probe"),
]


def _open(path, mode="r"):
    """Open without following a final symlink, so a read can never be redirected into /opt."""
    return os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), mode)


def _sha(path):
    with _open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def _load(path):
    assert path.exists() and path.stat().st_size > 0, (
        f"{path.name}: no depots.json was written for this run"
    )
    with _open(path) as fh:
        text = fh.read()
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        pytest.fail(f"{path.name}: not valid JSON ({e}): {text[:200]!r}")


def _key(path):
    with open(path) as fh:
        return json.load(fh)


def _policy(data_dir):
    with open(data_dir / "policy.json") as fh:
        return json.load(fh)


def _programme_hours(data_dir):
    """Hours worked in the programme year for every depot that exists in it: the register's payroll
    hours and agency hours together, with a row the register marks merged_into another folded into
    that depot, which is how instruction.md and the README define a depot and its hours. A merged
    id is not a depot and is not a key here."""
    year = _policy(data_dir)["programme_year"]
    with open(data_dir / "depots.csv", newline="") as fh:
        rows = list(csv.DictReader(fh))
    worked = lambda row: int(row[f"labour_hours_{year}"]) + int(row[f"agency_hours_{year}"])
    merged = {row["depot"]: row["merged_into"] for row in rows}

    def survivor(d):
        """The depot left standing at the end of d's chain of mergers. A yard folded into a yard
        that was itself folded on is carried all the way to the end of the chain, which is what the
        README tells the candidate to do; a register that pointed a chain back at itself would name
        no survivor at all, and that row is left out rather than guessed at."""
        seen = set()
        while merged.get(d) and d not in seen:
            seen.add(d)
            d = merged[d]
        return None if merged.get(d) else d

    hours = {row["depot"]: worked(row) for row in rows if not row["merged_into"]}
    for row in rows:
        if row["merged_into"]:
            end = survivor(row["depot"])
            if end is not None:
                hours[end] += worked(row)
    return hours


def test_shipped_export_unmodified():
    """The six files in /app/data are byte-identical to what shipped."""
    for name, sha in SHIPPED_SHA.items():
        assert _sha(SHIPPED_DATA / name) == sha, f"{name} was altered"


@pytest.mark.parametrize("run_path,key_path,data_dir", RUNS)
def test_list_shape(run_path, key_path, data_dir):
    """One object with exactly the key depots: an array of exactly list_size depot ids from that
    run's depots.csv, none of them marked merged into another, no repeats."""
    r = _load(run_path)
    assert isinstance(r, dict) and set(r) == {"depots"}, (
        f"{run_path.name}: expected exactly the key depots"
    )
    lst = r["depots"]
    assert isinstance(lst, list), f"{run_path.name}: depots is not an array"
    assert all(isinstance(x, str) for x in lst), f"{run_path.name}: depots must be depot ids"
    size = _policy(data_dir)["list_size"]
    assert len(lst) == size, f"{run_path.name}: {len(lst)} depots listed, the policy asks for exactly {size}"
    assert len(lst) == len(set(lst)), f"{run_path.name}: a depot is listed more than once"
    unknown = sorted(set(lst) - set(_programme_hours(data_dir)))
    assert not unknown, (
        f"{run_path.name}: {len(unknown)} listed ids are not depots of this export (not in depots.csv, "
        f"or merged into another depot), e.g. {unknown[:5]}"
    )


@pytest.mark.parametrize("run_path,key_path,data_dir", RUNS)
def test_programme_year_rate(run_path, key_path, data_dir):
    """Over the programme year the listed depots' incidents per hour worked come to at least
    minimum_rate_ratio times the whole network's."""
    lst = _load(run_path)["depots"]
    counts = _key(key_path)["programme_year_incidents"]
    hours = _programme_hours(data_dir)
    floor = _policy(data_dir)["minimum_rate_ratio"]
    unknown = sorted(set(lst) - set(hours))
    assert not unknown, (
        f"{run_path.name}: {len(unknown)} listed ids are not depots of this export, e.g. {unknown[:5]}, "
        f"so their programme-year rate is undefined"
    )
    listed = sum(counts[d] for d in lst) / sum(hours[d] for d in lst)
    network = sum(counts.values()) / sum(hours.values())
    ratio = listed / network
    assert ratio >= floor, (
        f"{run_path.name}: the listed depots ran at {ratio:.3f} times the network's incident rate in the "
        f"programme year, under the {floor:.2f} the policy requires. A depot's place in the league table "
        f"is not the same thing as its incident rate"
    )


