#!/bin/bash

# Verifier entrypoint. Runs in the verifier container, not the agent's: it sees only the paths
# declared in `artifacts`. All tooling is baked into tests/Dockerfile; nothing is fetched here.

set -uo pipefail

mkdir -p /logs/verifier
echo 0 > /logs/verifier/reward.txt

# Fold stderr into stdout: only stdout survives into the feedback bundle.
exec 2>&1

as_runner() {
  setpriv --clear-groups --no-new-privs --reuid runner --regid runner "$@"
}

# The shipped tests/ directory lands here at runtime, so the verifier's own code sits under
# /tests just as agent-authored code is about to run. Close it to the build user first: root still
# reads it, `runner` cannot traverse it. If it is still reachable the run is abandoned with reward
# 0 rather than graded. `test -r` on a file is not enough on its own: access(2) answers true for a
# chmod 700 directory the user cannot actually read, so a listing of the key directory is tried too.
chmod 700 /tests 2>/dev/null || true
chmod 700 /logs/verifier 2>/dev/null || true
if as_runner bash -c 'test -r /tests/test_outputs.py || ls /opt/golden || ls /opt/hidden' >/dev/null 2>&1; then
  echo "FATAL: /tests or the answer keys are still reachable by the unprivileged build user;"
  echo "the verifier's code and keys are exposed to agent-authored code, so this run cannot be graded."
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
echo "verifier files closed to the unprivileged build user"

# The shipped export is checked back against its hashes by pytest, so it stays where it landed,
# read-only. A root-owned pristine copy of the agent's project is kept so each build starts from
# exactly what was collected; cp -a keeps the agent's file modes, so write bits are stripped.
chmod -R a-w /app/data
cp -a /app/watch /opt/watch_pristine
# cp -a keeps the agent's modes, so the pristine copy would otherwise be a second readable
# copy of everything it shipped, including anything it meant to load at run time.
chmod -R go-rwx /opt/watch_pristine

# The task states the tool lives in Free Pascal and that the box carries nothing past its
# run-time units. This image ships a Python interpreter because pytest scores the result with it,
# and the compiler and shells are here because the tool has to be built. All of them, and every other executable on the system paths, are closed to
# the build user for the seconds the binary runs, so the graded figures cannot come out of a
# python or awk the binary shells out to, and reopened straight after. Root is unaffected.
TOOLS="$( { find /usr/local/bin /usr/local/sbin /usr/bin /bin /usr/sbin /sbin -xdev -type f -perm /111 2>/dev/null;
             for l in $(find /usr/local/bin /usr/bin /bin -xdev -type l 2>/dev/null); do t="$(readlink -f "$l")"; [ -f "$t" ] && echo "$t"; done; } \
  | sort -u | grep -v -E 'ld-linux|/ld\.so$' | grep -v -x -F -e "$(readlink -f /usr/bin/env)")"
# /usr/bin/env is what setpriv starts each run through, so it stays open; it is not a route to
# anything, since whatever it executes is checked on its own. Only regular files are listed: the
# merged /bin is itself a symlink to /usr/bin, and closing that directory would shut the whole
# tree, launcher included. The dynamic loader is left out as
# well: /usr/bin/ld.so links to it, and closing it would stop every dynamically linked program,
# the launcher included, not only the ones the agent's code might spawn.
close_tools() { for f in $TOOLS; do chmod 750 "$f" 2>/dev/null || true; done; }
open_tools()  { for f in $TOOLS; do chmod 755 "$f" 2>/dev/null || true; done; }
trap open_tools EXIT

# Compile the collected sources ourselves, as the build user, from the directory the instruction
# documents. The agent's build.sh is not run: the instruction says the list comes out of the
# Pascal, and a build script that did the work some other way would otherwise pass with the
# stub still in place. fpc is told where to put its object files so nothing lands beside the
# sources. The binary that build produces is what is run.
rm -rf /app/watch
cp -a /opt/watch_pristine /app/watch
rm -f /app/watch/watch
rm -rf /app/watch/obj && mkdir -p /app/watch/obj
chown -R runner:runner /app/watch /app/out
setsid \
  setpriv --clear-groups --no-new-privs --reuid runner --regid runner \
  bash -c 'cd /app/watch && fpc -O2 -Mobjfpc -Sh -FEobj -FUobj -Fu/app/watch/src -Fi/app/watch/src -o/app/watch/watch src/watch.pas' &
bpid=$!
wait "$bpid"
bstatus=$?
echo "build exit status: $bstatus"
# setsid makes the child a session leader, so its group id is its own pid and can be addressed
# directly. Reading it out of /proc races setsid and has taken down the verifier on sibling tasks.
kill -TERM -- -"$bpid" 2>/dev/null || true
kill -KILL -- -"$bpid" 2>/dev/null || true
as_runner bash -c 'kill -9 -1' 2>/dev/null || true
[ "$bstatus" -eq 0 ] && [ -x /app/watch/watch ] || echo "the collected sources did not build into /app/watch/watch"

# Everything the build produced now belongs to root. The build user keeps exactly one thing it can
# run, the binary just built, and nothing it can read beside it, so a helper shipped in the project
# cannot be executed and cannot be loaded as a library either (a shared object needs only the read
# bit, which is why stripping execute bits alone was not enough). It also cannot chmod any of it
# back, because it no longer owns any of it.
chown -R root:root /app/watch
find /app/watch -type d -exec chmod 755 {} +
find /app/watch -type f -exec chmod 600 {} +
[ -f /app/watch/watch ] && chmod 755 /app/watch/watch

# /app/data and /app/out are declared artifacts, so the agent can leave files in both. The export
# is six files and all six are hashed by test_outputs.py, README.md included, so an unhashed and
# still-readable file cannot be used to smuggle anything into a run; anything else the agent
# parked there is not part of the export and goes before any graded run. That means anything at
# all that is not one of the six names at the top level, directories included, so a copy of an
# interpreter filed under an allowed name inside a subdirectory does not survive. What does
# survive loses its execute bits, since the tool closure below only reaches the system paths;
# read access to the six shipped files stays open because the binary has to read them, which is
# why they are hashed rather than just closed.
find /app/data -mindepth 1 -maxdepth 1 \
  ! -name depots.csv ! -name incidents.csv ! -name insurer_claims.csv \
  ! -name pilot_year.csv ! -name policy.json ! -name README.md -exec rm -rf {} +
find /app/data -type f -exec chmod a-x {} +

# run_once <data-dir> <output-path> <capture-path>: run the built binary on an export, as the
# build user, with every tool closed, from /app/watch, and move what it wrote to a root-only
# path. Each run is given its own output path, so a program that writes a fixed destination
# rather than the one it is handed fails the second run. Only a regular file is ever staged:
# the binary cannot read the keys, but it can drop a symlink at the output path pointing into
# /opt, and pytest, running as root, would then read the verifier's own truth back as the
# agent's figures. Before each run every file under the project except the binary just built
# loses its execute bits, so a helper shipped beside the sources cannot be run from the Pascal.
run_once() {
  local data="$1" outfile="$2" out="$3" pid
  rm -rf /app/out && mkdir -p /app/out && chown runner:runner /app/out
  close_tools
  setsid \
    setpriv --clear-groups --no-new-privs --reuid runner --regid runner \
    env -C /app/watch HOME=/home/runner /app/watch/watch "$data" "$outfile" &
  pid=$!
  wait "$pid"
  echo "run exit status: $? ($data)"
  open_tools
  kill -TERM -- -"$pid" 2>/dev/null || true
  kill -KILL -- -"$pid" 2>/dev/null || true
  as_runner bash -c 'kill -9 -1' 2>/dev/null || true
  if [ -L "$outfile" ] || [ ! -f "$outfile" ]; then
    echo "no regular $outfile was produced for $data (absent, or not a regular file)"
    rm -f "$outfile"
  else
    mv "$outfile" "$out"
    chown root:root "$out" 2>/dev/null || true
    chmod 600 "$out" 2>/dev/null || true
  fi
}

echo "=== the export that shipped in the agent's image ==="
run_once /app/data /app/out/depots.json /opt/run_shipped.json

# Then the other network. Its export is staged only now, after the build has finished and every
# process it started is gone, into a fresh directory the binary has never seen, so nothing that
# ran during compilation could have had it on disk to read.
staged="$(mktemp -d /app/export_XXXXXXXX)"
cp /opt/hidden/data/*.csv /opt/hidden/data/policy.json /opt/hidden/data/README.md "$staged"/
chown -R runner:runner "$staged"
chmod -R a-w "$staged"
echo "=== the same binary on the other network's export ==="
run_once "$staged" /app/out/watch_second.json /opt/run_hidden.json
rm -rf "$staged"

# Nothing the agent started may be alive while pytest runs or while the reward is written.
as_runner bash -c 'kill -9 -1' 2>/dev/null || true

# -P keeps the working directory off sys.path, so a pytest.py dropped into /app by the binary
# cannot shadow the suite. The interpreter is called by full path, not through PATH.
cd /tests
/usr/local/bin/python3 -P -m pytest -o cache_dir=/tmp/pytest_cache \
  --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi

# Harbor grades from reward.txt, never from this script's exit status.
exit 0
