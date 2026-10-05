#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
timeline_test_dir=$(mktemp -d /tmp/broll-timeline-tests.XXXXXX)
trap 'rm -rf "$timeline_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ScriptTimelineTests.swift -o "$timeline_test_dir/timeline-tests"
"$timeline_test_dir/timeline-tests"
