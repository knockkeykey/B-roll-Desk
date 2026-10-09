#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
script_test_dir=$(mktemp -d /tmp/broll-script-import-tests.XXXXXX)
trap 'rm -rf "$script_test_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library \
  BRollDeskApp/Models.swift BRollDeskApp/AnimationWorkflow.swift \
  BRollDeskApp/AppModel.swift BRollDeskApp/FileDropDelegate.swift \
  Tests/ScriptImportPersistenceTests.swift -o "$script_test_dir/script-tests"
"$script_test_dir/script-tests"
