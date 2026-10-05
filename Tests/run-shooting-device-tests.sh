#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
device_test_dir=$(mktemp -d /tmp/broll-device-tests.XXXXXX)
trap 'rm -rf "$device_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ShootingDeviceTests.swift -o "$device_test_dir/device-tests"
"$device_test_dir/device-tests"
