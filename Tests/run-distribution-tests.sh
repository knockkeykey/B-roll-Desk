#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
distribution_test_dir=$(mktemp -d /tmp/broll-distribution-tests.XXXXXX)
trap 'rm -rf "$distribution_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ScriptDistributionTests.swift -o "$distribution_test_dir/distribution-tests"
"$distribution_test_dir/distribution-tests"
