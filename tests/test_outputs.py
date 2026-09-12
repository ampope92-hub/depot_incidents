"""Verifier for the programme list.

test.sh compiles the agent's Pascal itself, runs the binary once on the export that shipped and
once on another network's export it has never seen, and captures each depots.json root-only.
This module only reads those captures and the keys under /opt: what every depot logged in the
programme year once logging was mandatory. It never runs agent code.

Every bar here is stated in instruction.md, and the same bar applies to both runs.
"""
import csv
import hashlib
import json
import os
import pathlib

import pytest

SHIPPED_RUN = pathlib.Path("/opt/run_shipped.json")
HIDDEN_RUN = pathlib.Path("/opt/run_hidden.json")
SHIPPED_KEY = pathlib.Path("/opt/golden/key.json")
HIDDEN_KEY = pathlib.Path("/opt/hidden/key.json")
SHIPPED_DATA = pathlib.Path("/app/data")
HIDDEN_DATA = pathlib.Path("/opt/hidden/data")

SHIPPED_SHA = {
    "incidents.csv": "0517b7d9571d9165783625a414a9c5b169a0633630b3b55865574eb0ed15a554",
    "insurer_claims.csv": "108ff847e33fc27f57704fc9f94e0b75af10f3fecbaee79c20529af8a71495fc",
    "depots.csv": "5e61350e742ce436a818389c0e842e04b9ab7a70820fb6b6467954a46475f1c5",
    "policy.json": "880b6a2e8d44c0ebbc4d2120548eb1e7251841be8bde5682965c159dd5bcf6c7",
    "pilot_year.csv": "066fb5a26d0fb2b1bd3151b84d9731b8cc206f762d2ccc33105f0c71cd9f951d",
    # README.md is hashed too: it is readable and its execute bit alone is stripped, and
    # dlopen()/mmap(PROT_EXEC) need only the read bit, so an unhashed README could carry a
    # dynamically loaded payload without tripping any other check. Pinning it closes that off
    # the same way the other five files are closed: any change to it fails this test.
    "README.md": "9ade693e554e7a585f15f48f23fbd658cc967b7775908602c9ed4b63cdd1a3cc",
}

RUNS = [
    pytest.param(SHIPPED_RUN, SHIPPED_KEY, SHIPPED_DATA, id="shipped"),
    pytest.param(HIDDEN_RUN, HIDDEN_KEY, HIDDEN_DATA, id="hidden"),
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
    hours = {row["depot"]: worked(row) for row in rows if not row["merged_into"]}
    for row in rows:
        if row["merged_into"]:
            hours[row["merged_into"]] += worked(row)
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


