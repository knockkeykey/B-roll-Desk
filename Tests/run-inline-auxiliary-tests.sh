#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
inline_test_dir=$(mktemp -d /tmp/broll-inline-auxiliary-tests.XXXXXX)
trap 'rm -rf "$inline_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/InlineAndAuxiliaryTests.swift -o "$inline_test_dir/inline-tests"
"$inline_test_dir/inline-tests"
