#!/usr/bin/env bats
# Tests for bin/code-review-loop — argument parsing and validation.

load test_helper

BIN="$PROJECT_ROOT/bin/code-review-loop"

@test "code-review-loop --help prints usage and exits 0" {
    run "$BIN" --help
    assert_success
    assert_output --partial "Usage: code-review-loop"
}

@test "code-review-loop -h prints usage and exits 0" {
    run "$BIN" -h
    assert_success
    assert_output --partial "Usage: code-review-loop"
}

@test "code-review-loop rejects unknown options" {
    run "$BIN" --bogus
    assert_output --partial "Unknown option"
}

@test "code-review-loop --max-iterations without value shows error" {
    run "$BIN" -m
    assert_output --partial "requires a value"
}

@test "code-review-loop rejects invalid agent name" {
    # Prompt files won't exist, but agent validation happens first
    run "$BIN" --editor gpt4
    assert_failure
    assert_output --partial "Unknown agent"
}
