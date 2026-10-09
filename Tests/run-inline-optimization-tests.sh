#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
inline_optimization_dir=$(mktemp -d /tmp/broll-inline-optimization.XXXXXX)
trap 'rm -rf "$inline_optimization_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/InlineOptimizationTests.swift -o "$inline_optimization_dir/tests"
"$inline_optimization_dir/tests"
