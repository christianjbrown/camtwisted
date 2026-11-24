#!/bin/sh
# The repository's one check. Runs every test, requires every line, function
# and region of the libraries and the audio driver to be covered (see tools/coverage_gate.py for
# the few files left out and why), and builds the app and camera extension.
set -eu

cd "$(dirname "$0")/.."

SOURCES="/Sources/"
PRODUCTS=".build/out/Products/Debug"

echo "== Tests"
TEST_LOG="$(mktemp)"
REPORT="$(mktemp)"
BUILD_LOG="$(mktemp)"
trap 'rm -f "$TEST_LOG" "$REPORT"' EXIT
if swift test --enable-code-coverage >"$TEST_LOG" 2>&1; then
    grep -E "Executed [0-9]+ tests" "$TEST_LOG" | sort -u | tail -2
else
    grep -E "\.swift:[0-9]+: error|error:" "$TEST_LOG" | grep -v "CoreData" | cut -c1-300 || true
    echo "Tests failed"
    exit 1
fi

echo "== Coverage: lines, functions and regions"
xcrun llvm-cov export -format=text -instr-profile "$PRODUCTS/codecov/default.profdata" \
    "$PRODUCTS/CamTwistRenderingTests.xctest/Contents/MacOS/CamTwistRenderingTests" \
    -object "$PRODUCTS/CamTwistCoreTests.xctest/Contents/MacOS/CamTwistCoreTests" \
    -object "$PRODUCTS/CamTwistControlTests.xctest/Contents/MacOS/CamTwistControlTests" \
    -object "$PRODUCTS/CamTwistAudioDriverTests.xctest/Contents/MacOS/CamTwistAudioDriverTests" >"$REPORT" 2>/dev/null
# shellcheck disable=SC2086
python3 tools/coverage_gate.py "$REPORT" "$SOURCES" || { echo "Coverage is not complete"; exit 1; }

echo "== App and camera extension build"
[ -f Config/Signing.xcconfig ] || cp Config/Signing.example.xcconfig Config/Signing.xcconfig
xcodegen generate >/dev/null
xcodebuild -project CamTwisted.xcodeproj -scheme CamTwisted -configuration Debug \
    -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build >"$BUILD_LOG" 2>&1 || true
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$BUILD_LOG" | sort -u
# The build's own verdict, not the app left behind by an earlier one.
grep -q "BUILD SUCCEEDED" "$BUILD_LOG" || { echo "Build failed"; exit 1; }
echo "== All checks passed"
