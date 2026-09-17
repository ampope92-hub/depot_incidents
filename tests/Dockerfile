# Verifier image. Runs in its own container: it sees only the paths declared in `artifacts`.
# It recompiles the agent's Pascal and runs it, so it needs fpc; it scores the result with the
# standard library, so it needs nothing else. There is no dependency tree to pre-build here, the
# tool is written against the Free Pascal run-time units, which is why this image has no skeleton
# stage and no stale-binary problem.

# The graded runs execute the agent's compiled binary. This small launcher wraps that exec in a
# seccomp filter (no-new-privs plus a raw BPF policy) so the binary cannot run native code from an
# anonymous, path-less file, closing the memfd_create+fexecve route while leaving ordinary file
# work untouched. It is built from source in a throwaway stage with a C compiler and statically
# linked, so the final image carries only the finished binary and no compiler.
FROM public.ecr.aws/docker/library/python:3.13-slim-bookworm@sha256:01f42367a0a94ad4bc17111776fd66e3500c1d87c15bbd6055b7371d39c124fb AS launcher
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
COPY launch.c /tmp/launch.c
RUN gcc -O2 -static -Wall -o /watch_launch /tmp/launch.c

FROM public.ecr.aws/docker/library/python:3.13-slim-bookworm@sha256:01f42367a0a94ad4bc17111776fd66e3500c1d87c15bbd6055b7371d39c124fb

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
    && apt-get install -y --no-install-recommends fpc \
    && rm -rf /var/lib/apt/lists/*

# Verifier tooling, pinned. Nothing is installed at trial time.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --require-hashes --no-deps -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

# The statically linked launcher, built in the throwaway stage above.
COPY --from=launcher /watch_launch /usr/local/bin/watch_launch
RUN chmod 755 /usr/local/bin/watch_launch

# test.sh recompiles and runs the agent's program, so agent-authored code executes in this image,
# and this image holds the answer key. That code runs as `runner`, never root.
RUN useradd --create-home --uid 10001 --shell /bin/bash runner

# Artifact landing directories must exist before Harbor uploads the declared artifacts.
RUN mkdir -p /app/watch/src /app/data /app/out

# /app is runner-owned so the build can write its binary and its output there, but sticky so
# runner cannot rename or delete the root-owned export beside it.
RUN chown -R runner:runner /app \
    && chmod 1755 /app

# The key for the shipped network, at a path Harbor does not reserve, readable only by root. /tests
# is a runtime mount, permissions set on it here are ineffective and a documented cause of verifier
# failure, so the answer key cannot be protected there.
COPY golden /opt/golden
RUN chmod 700 /opt/golden && chmod 600 /opt/golden/*

# The other network's export and key. test.sh stages them after the build and runs the agent's
# binary a second time, which is what proves the list is worked out at run time rather than
# written into the source.
COPY hidden /opt/hidden
RUN chmod -R go-rwx /opt/hidden

# A third network, graded the same way as a second run. Two fixed exports can be told apart by
# their policy values and answered with two embedded qualifying lists; a third one with its own
# policy values closes that, since there is no map for it to paste.
COPY third /opt/third
RUN chmod -R go-rwx /opt/third

COPY . /tests/

WORKDIR /app
