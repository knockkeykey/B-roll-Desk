#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
filter_test_dir=$(mktemp -d /tmp/broll-filter-tests.XXXXXX)
trap 'rm -rf "$filter_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ScriptFilterTests.swift -o "$filter_test_dir/filter-tests"
"$filter_test_dir/filter-tests"
