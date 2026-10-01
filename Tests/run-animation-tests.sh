#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
test_dir=$(mktemp -d /tmp/broll-animation-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/AnimationWorkflowTests.swift -o "$test_dir/workflow-tests"
"$test_dir/workflow-tests"
