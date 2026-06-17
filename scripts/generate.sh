#!/usr/bin/env bash
# Generate AUSeq.xcodeproj from project.yml via XcodeGen.
set -euo pipefail
cd "$(dirname "$0")/.."

XCODEGEN="${XCODEGEN:-$HOME/tools/xcodegen/bin/xcodegen}"
if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN="xcodegen"
elif [ ! -x "$XCODEGEN" ]; then
  echo "error: xcodegen not found. Install from https://github.com/yonaskolb/XcodeGen" >&2
  echo "       or set XCODEGEN=/path/to/xcodegen" >&2
  exit 1
fi

"$XCODEGEN" generate
echo "Generated AUSeq.xcodeproj"
