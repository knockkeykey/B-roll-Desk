#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
inline_performance_dir=$(mktemp -d /tmp/broll-inline-performance.XXXXXX)
trap 'rm -rf "$inline_performance_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/InlinePerformanceTests.swift -o "$inline_performance_dir/tests"
if (( $# )); then
  "$inline_performance_dir/tests" "$@"
else
  "$inline_performance_dir/tests" "$inline_performance_dir/fixture"
fi
