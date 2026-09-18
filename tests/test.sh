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
if as_runner bash -c 'test -r /tests/test_outputs.py || ls /opt/golden || ls /opt/hidden || ls /opt/third' >/dev/null 2>&1; then
  echo "FATAL: /tests or the answer keys are still reachable by the unprivileged build user;"
  echo "the verifier's code and keys are exposed to agent-authored code, so this run cannot be graded."
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
echo "verifier files closed to the unprivileged build user"

# /app/data and /app/out are declared artifacts exactly like src/, so anything either one
# holds at build time is just as reachable from an fpc {$link} directive naming an absolute
# path as a file sitting under src/ would be. Both are pruned to what a run actually needs
# now, before the pristine copy is taken and well before fpc runs, instead of only after the
# build as before. /app/data keeps just the six shipped names (instruction.md: "Leave the six
# files in /app/data as they are"); anything else at its top level, directories included, goes,
# and what remains loses its execute bits. /app/out is emptied outright: nothing legitimate
# needs to be there before the binary that will write into it has even been built.
find /app/data -mindepth 1 -maxdepth 1 \
  ! -name depots.csv ! -name incidents.csv ! -name insurer_claims.csv \
  ! -name pilot_year.csv ! -name policy.json ! -name README.md -exec rm -rf {} +
find /app/data -type f -exec chmod a-x {} +
rm -rf /app/out && mkdir -p /app/out

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
  | sort -u | grep -v -E 'ld-linux|/ld\.so$' | grep -v -x -F -e "$(readlink -f /usr/bin/env)" -e /usr/local/bin/watch_launch)"
# /usr/bin/env is what setpriv starts each run through, so it stays open; it is not a route to
# anything, since whatever it executes is checked on its own. watch_launch stays open for the same
# reason: it is the wrapper that starts the binary under the seccomp filter, and it runs nothing but
# the one binary it is handed. Only regular files are listed: the
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
# The binary is built from the Pascal under src/ and nothing else of the agent's, and everything
# under src/ comes along to the build, whatever its name or extension: a Pascal unit is not
# always a .pas, an include is not always an .inc, and stripping by extension deleted
# contract-legal source before fpc ever ran. So
# nothing under src/ is removed on account of its name; the one thing that must not happen, a
# non-Pascal file reaching the linker, is stopped by the link-input check below instead, which
# reads what fpc actually resolved rather than guessing from a filename. build.sh is a declared
# artifact collected into /app/watch for the agent's own use; the verifier compiles src/watch.pas
# itself and never sources it, so it is removed rather than left where an {$L /app/watch/build.sh}
# directive could hand it to the linker. This runs as root, before the tree is handed to the
# build user, so it cannot be raced or skipped.
rm -f /app/watch/build.sh
chown -R runner:runner /app/watch
# Second, and the real backstop: fpc is run with -Cn, which compiles the Pascal to objects and
# writes the link script it would hand to ld, but stops before the link. A correct project links
# only fpc's own compiled objects under obj/ and the Free Pascal run-time units under the fpc
# directory. An {$L}, {$linklib} or {$librarypath} directive naming anything else -- an object,
# a text linker script, a library, whatever its name, extension or content -- shows up in that
# link script as an extra INPUT entry, and the link is refused. This checks the link inputs fpc
# actually resolved, not the Pascal source, so it needs no scan for a directive and a renamed or
# text-format payload has no way past it.
setsid \
  setpriv --clear-groups --no-new-privs --reuid runner --regid runner \
  bash -c 'cd /app/watch && fpc -Cn -O2 -Mobjfpc -Sh -FEobj -FUobj -Fu/app/watch/src -Fi/app/watch/src -o/app/watch/watch src/watch.pas' &
bpid=$!
wait "$bpid"
bstatus=$?
echo "compile exit status: $bstatus"
# setsid makes the child a session leader, so its group id is its own pid and can be addressed
# directly. Reading it out of /proc races setsid and has taken down the verifier on sibling tasks.
kill -TERM -- -"$bpid" 2>/dev/null || true
kill -KILL -- -"$bpid" 2>/dev/null || true
as_runner bash -c 'kill -9 -1' 2>/dev/null || true

# Read every INPUT() token out of fpc's generated link script(s) and reject the build if any one
# is neither an object fpc just produced under obj/ nor a run-time unit under the fpc directory.
link_ok=1
[ "$bstatus" -eq 0 ] || link_ok=0
if [ "$link_ok" -eq 1 ]; then
  for res in /app/watch/link*.res; do
    [ -f "$res" ] || continue
    bad="$(awk '
      { line = $0 }
      infield == 0 && line ~ /INPUT[ \t]*\(/ { infield = 1; sub(/.*INPUT[ \t]*\(/, "", line) }
      infield == 1 {
        rest = line
        if (rest ~ /\)/) { sub(/\).*/, "", rest); infield = 0 }
        n = split(rest, a, /[ \t]+/)
        for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
      }
    ' "$res" | grep -vE '^/usr/lib/x86_64-linux-gnu/fpc/' | grep -vE '^obj/[A-Za-z0-9_]+\.o$' || true)"
    if [ -n "$bad" ]; then
      echo "the collected sources hand the linker a file that is not fpc's own Pascal object: $(echo "$bad" | tr '\n' ' ')"
      link_ok=0
    fi
  done
fi

# Link only when the inputs checked out, as the build user, with fpc's own generated command.
if [ "$link_ok" -eq 1 ]; then
  setsid \
    setpriv --clear-groups --no-new-privs --reuid runner --regid runner \
    bash -c 'cd /app/watch && sh ppas.sh' &
  lpid=$!
  wait "$lpid"
  lstatus=$?
  echo "link exit status: $lstatus"
  kill -TERM -- -"$lpid" 2>/dev/null || true
  kill -KILL -- -"$lpid" 2>/dev/null || true
  as_runner bash -c 'kill -9 -1' 2>/dev/null || true
fi
[ "$link_ok" -eq 1 ] && [ -x /app/watch/watch ] || echo "the collected sources did not build into /app/watch/watch"

# Everything the build produced now belongs to root. The build user keeps exactly one thing it can
# run, the binary just built, and nothing it can read beside it, so a helper shipped in the project
# cannot be executed and cannot be loaded as a library either (a shared object needs only the read
# bit, which is why stripping execute bits alone was not enough). It also cannot chmod any of it
# back, because it no longer owns any of it.
chown -R root:root /app/watch
find /app/watch -type d -exec chmod 755 {} +
find /app/watch -type f -exec chmod 600 {} +
[ -f /app/watch/watch ] && chmod 755 /app/watch/watch

# /app/data was already pruned to the six shipped names and had its execute bits stripped
# above, before the build; it has been read-only (chmod a-w) since, and the build user has no
# privilege to undo that, so nothing new can have appeared there since. All six are hashed by
# test_outputs.py, README.md included, so an unhashed and still-readable file cannot be used to
# smuggle anything into a run either.

# The build user gets no writable directory for the runs, so a verifier-aware program cannot
# write a native helper somewhere and execute it. /app, the runner's home and the world-writable
# temp directories are all closed to it here, and each run's output is a single root-owned file
# it can only truncate and rewrite (below), inside a root-owned directory it cannot drop a
# sibling into. The one writable thing in the whole tree is that output file, and it never
# carries an execute bit and cannot be chmod'd by a user that does not own it. The remaining way
# to run native code without a file at all -- an anonymous in-memory executable from
# memfd_create run with fexecve -- is closed by the seccomp filter watch_launch installs around
# each run (below), which denies those calls, so there is no path, named or anonymous, to native
# code outside the compiled Pascal.
chown root:root /app && chmod 755 /app
rm -rf /app/out && mkdir -p /app/out && chown root:root /app/out && chmod 755 /app/out
chown -R root:root /home/runner && chmod -R go-w /home/runner
chmod 0755 /tmp /var/tmp /dev/shm
for d in /app /app/out /tmp /var/tmp /dev/shm /home/runner; do
  if as_runner test -w "$d" 2>/dev/null; then
    echo "FATAL: $d is writable by the unprivileged build user; a native helper could be dropped"
    echo "and executed there, so the run cannot be graded as the binary built from the Pascal."
    echo 0 > /logs/verifier/reward.txt
    exit 0
  fi
done
echo "no directory is writable by the unprivileged build user"

# run_once <data-dir> <output-path> <capture-path>: run the built binary on an export, as the
# build user, with every tool closed, from /app/watch, and move what it wrote to a root-only
# path. Each run is given its own output path, so a program that writes a fixed destination
# rather than the one it is handed fails the second run. The output path is pre-created by root
# as an empty, never-executable regular file at mode 0666, so the build user can open it for
# reading and writing and truncate it in place: every ordinary Pascal creation route works on it
# -- a text Rewrite, a TStringList.SaveToFile, a TFileStream.Create with fmCreate. What it cannot
# do is chmod it, rename it or replace it, or create a sibling temporary file to rename over it,
# because it does not own the file and the directory that holds it is root-owned and not writable.
# So the JSON has to be written straight into the file it is handed, which is what the instruction
# says is there for it; a regular file is the only thing that can end up at that path, so the
# binary cannot leave a symlink pointing into /opt and have pytest read the verifier's own truth
# back as the agent's figures, and it has nowhere to drop and run a native helper. Before each run
# every file under the project except the binary just built has already lost its execute bits, so
# a helper shipped beside the sources cannot be run from the Pascal.
run_once() {
  local data="$1" outfile="$2" out="$3" pid
  rm -rf /app/out && mkdir -p /app/out && chown root:root /app/out && chmod 755 /app/out
  : > "$outfile" && chown root:root "$outfile" && chmod 0666 "$outfile"
  close_tools
  # The binary is started through watch_launch, which installs a seccomp filter and then execs it.
  # The filter denies memfd_create and execveat, so the binary cannot open an anonymous, path-less
  # file, write native code into it and run it (fexecve); with no writable directory either, there
  # is nowhere at all for a dropped-in native helper to come from: nothing else on the box runs
  # while the binary does, which is what the instruction states. Ordinary file work is unaffected.
  setsid \
    setpriv --clear-groups --no-new-privs --reuid runner --regid runner \
    env -C /app/watch HOME=/home/runner /usr/local/bin/watch_launch /app/watch/watch "$data" "$outfile" &
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
# The export is read-only input: stage it root-owned so the unprivileged runner cannot chmod its
# own copy back and rewrite it. The directory is root-owned 0755 (traversable, not writable) and
# each file 0444 (world-readable), so the binary reads every file and owns none of them.
chown -R root:root "$staged"
chmod 755 "$staged"
find "$staged" -type f -exec chmod 444 {} +
echo "=== the same binary on the other network's export ==="
run_once "$staged" /app/out/watch_second.json /opt/run_hidden.json
rm -rf "$staged"

# A third network, staged the same way, only after the second run's process is gone. Two fixed
# exports can be told apart by their policy values and answered from two lists pasted into the
# source; a third with its own policy values leaves that dispatch nothing to match.
staged3="$(mktemp -d /app/export_XXXXXXXX)"
cp /opt/third/data/*.csv /opt/third/data/policy.json /opt/third/data/README.md "$staged3"/
chown -R root:root "$staged3"
chmod 755 "$staged3"
find "$staged3" -type f -exec chmod 444 {} +
echo "=== the same binary on the third network's export ==="
run_once "$staged3" /app/out/watch_third.json /opt/run_third.json
rm -rf "$staged3"

# A fourth run: the shipped export again, with its policy.json serialised the way another tool
# would write it (no indentation, keys in another order, one key spelled with a JSON string
# escape). It decodes to the same object, so the same list clears the same key; a program that
# searched the policy text for a literal key name instead of decoding the JSON fails here and
# nowhere else. The data directory pytest reads for this run is assembled root-only under /opt
# from the shipped files, which the hash check covers, and the probe policy.
mkdir -p /opt/probe_data
cp /app/data/*.csv /app/data/README.md /opt/probe_data/
cp /opt/probe/policy.json /opt/probe_data/policy.json
chmod 700 /opt/probe_data && chmod 600 /opt/probe_data/*
staged4="$(mktemp -d /app/export_XXXXXXXX)"
cp /opt/probe_data/* "$staged4"/
chown -R root:root "$staged4"
chmod 755 "$staged4"
find "$staged4" -type f -exec chmod 444 {} +
echo "=== the same binary on the shipped export with its policy re-serialised ==="
run_once "$staged4" /app/out/watch_probe.json /opt/run_probe.json
rm -rf "$staged4"

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
