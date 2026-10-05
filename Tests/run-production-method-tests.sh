#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
production_test_dir=$(mktemp -d /tmp/broll-production-tests.XXXXXX)
trap 'rm -rf "$production_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ProductionMethodTests.swift -o "$production_test_dir/production-tests"
"$production_test_dir/production-tests"
