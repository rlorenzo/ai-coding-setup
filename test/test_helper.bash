#!/usr/bin/env bash
# Shared test helper for BATS tests.
# Loaded via `load test_helper` at the top of each .bats file.

# Absolute path to the project root
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Load BATS helper libraries
load "$PROJECT_ROOT/test/bats/bats-support/load"
load "$PROJECT_ROOT/test/bats/bats-assert/load"

# ---- per-test setup/teardown ---------------------------------------------

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR

    # Override HOME so config file tests are isolated
    export REAL_HOME="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ---- helpers -------------------------------------------------------------

# Source the shared library in a clean state (reset double-source guard).
source_lib() {
    unset _LIB_REVIEW_LOOP_LOADED
    # shellcheck source=lib/lib-review-loop
    source "$PROJECT_ROOT/lib/lib-review-loop"
}
