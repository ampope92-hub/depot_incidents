# The safety team's analyst tooling is Free Pascal, so the agent's project is compiled with fpc.
# Canonical Python base: the harness runs on it, and nothing here needs a numerics stack.
FROM public.ecr.aws/docker/library/python:3.13-slim-bookworm@sha256:01f42367a0a94ad4bc17111776fd66e3500c1d87c15bbd6055b7371d39c124fb

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# fpc is the whole toolchain: the tool is written against the Free Pascal run-time units
# (SysUtils, Classes and friends), with no package fetched at solve time on an offline box.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        fpc \
        tmux \
        asciinema \
    && rm -rf /var/lib/apt/lists/*

# The project the agent completes, and the network's export.
COPY watch /app/watch
COPY data /app/data
RUN chmod +x /app/watch/build.sh && mkdir -p /app/watch/obj /app/out

# The graded runs serve the export read-only to an unprivileged user, so a solution must open
# its inputs for reading only. The agent works as root, where that constraint cannot be forced,
# but the export ships with its write bits cleared so the read-only intent is visible in the
# working tree; instruction.md states it plainly.
RUN chmod a-w /app/data/*

WORKDIR /app
