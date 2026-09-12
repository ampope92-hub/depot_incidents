#!/usr/bin/env bash
set -euo pipefail

# Picks the depots for the programme.
#
# The memo's league table is logged incidents per hour worked, and a depot's place in it is
# mostly how often its people log a minor incident, which is anywhere from hardly ever to
# nearly always. Severe incidents get logged regardless, every one carries an insurer claim,
# so severe incidents per hour worked over the logged years is what ranks the depots here,
# the severity read as a code and payroll and agency hours summed.
# Written out in watch.pas beside this file.
install -m 644 "$(dirname "$0")/watch.pas" /app/watch/src/watch.pas
bash /app/watch/build.sh
mkdir -p /app/out
/app/watch/watch /app/data /app/out/depots.json
