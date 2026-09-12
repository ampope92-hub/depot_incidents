#!/usr/bin/env bash
# Build the programme-list tool. Run it as: /app/watch/watch <data-dir> <output-json>
set -euo pipefail
cd /app/watch
fpc -O2 -Mobjfpc -Sh -FEobj -FUobj -o/app/watch/watch src/watch.pas
