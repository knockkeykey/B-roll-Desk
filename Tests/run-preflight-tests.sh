#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
preflight_test_dir=$(mktemp -d /tmp/broll-preflight-tests.XXXXXX)
trap 'rm -rf "$preflight_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ShootingPreflightTests.swift -o "$preflight_test_dir/preflight-tests"
"$preflight_test_dir/preflight-tests"
