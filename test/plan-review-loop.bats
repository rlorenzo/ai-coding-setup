#!/usr/bin/env bats
# Tests for bin/plan-review-loop — argument parsing and validation.

load test_helper

BIN="$PROJECT_ROOT/bin/plan-review-loop"

@test "plan-review-loop --help prints usage and exits 0" {
    run "$BIN" --help
    assert_success
    assert_output --partial "Usage: plan-review-loop"
}

@test "plan-review-loop -h prints usage and exits 0" {
    run "$BIN" -h
    assert_success
    assert_output --partial "Usage: plan-review-loop"
}

@test "plan-review-loop requires a plan file argument" {
    run "$BIN"
    # usage() exits 0 after printing the error, so check for the error message
    assert_output --partial "Plan file argument is required"
}

@test "plan-review-loop rejects unknown options" {
    run "$BIN" --bogus
    assert_output --partial "Unknown option"
}

@test "plan-review-loop rejects nonexistent plan file" {
    run "$BIN" /nonexistent/plan.md
    assert_failure
    assert_output --partial "Plan file not found"
}

@test "plan-review-loop rejects invalid agent name" {
    run "$BIN" --editor gpt4 /tmp/dummy.md
    assert_failure
    assert_output --partial "Unknown agent"
}
