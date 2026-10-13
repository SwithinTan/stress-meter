#!/bin/zsh
set -eu
cd "${0:A:h:h}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp/}stress-health-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -emit-module -emit-library -static \
  -module-name StressCore -emit-module-path "$test_dir/StressCore.swiftmodule" \
  Sources/StressCore/*.swift -o "$test_dir/libStressCore.a"
xcrun swiftc -swift-version 6 -parse-as-library -I "$test_dir" -L "$test_dir" -lStressCore \
  WatchApp/HealthKitProvider.swift scripts/HealthQueryLifecycleTests.swift \
  -o "$test_dir/HealthQueryLifecycleTests"
"$test_dir/HealthQueryLifecycleTests"
