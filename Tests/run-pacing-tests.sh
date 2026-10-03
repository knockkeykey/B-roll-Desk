#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
pacing_test_dir=$(mktemp -d /tmp/broll-pacing-tests.XXXXXX)
trap 'rm -rf "$pacing_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ARollPacingTests.swift -o "$pacing_test_dir/pacing-tests"
"$pacing_test_dir/pacing-tests"
