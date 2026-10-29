#!/usr/bin/env bash
# Monotonic build-number counter. Increments .build-number and echoes the new
# value. Call once per package build.
#
# Versioning (mandatory): the full version is <patch>.b<build>, e.g. 1.0.0.b7.
#   - <patch> = 1.0.x lives in control's Version; it only changes when Cosmin says so.
#   - <build> only ever goes up: this script never decreases it.
# CI passes LPRO_BUILD_NUMBER from the run number instead of this file.
set -euo pipefail
cd "$(dirname "$0")/.."
current=$(cat .build-number 2>/dev/null || echo 0)
next=$(( current + 1 ))
echo "$next" > .build-number
echo "$next"
