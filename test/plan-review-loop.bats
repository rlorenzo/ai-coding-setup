#!/usr/bin/env bats
# Tests for bin/plan-review-loop: argument parsing and validation.

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

# The loop is installed as a symlink into the clone, so an agent run inside
# this repo can rewrite the running script. The brace group parses it up front.
@test "plan-review-loop survives an agent rewriting the script mid-run" {
    mkdir -p "$BATS_TEST_TMPDIR/install/bin" "$BATS_TEST_TMPDIR/install/lib" \
        "$BATS_TEST_TMPDIR/repo/stub"
    cp "$BIN" "$BATS_TEST_TMPDIR/install/bin/plan-review-loop"
    cp "$PROJECT_ROOT/lib/lib-review-loop" "$BATS_TEST_TMPDIR/install/lib/lib-review-loop"
    export SELF_EDIT_TARGET="$BATS_TEST_TMPDIR/install/bin/plan-review-loop"
    export AI_CODING_SETUP_PROMPTS_DIR="$PROJECT_ROOT/prompts"

    cd "$BATS_TEST_TMPDIR/repo"
    git init -q
    echo "# Plan" > PLAN-x.md
    # Truncate in place, never rename, or bash keeps the original inode.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' \
        'printf "#!/usr/bin/env bash\necho CLOBBERED\n" > "$SELF_EDIT_TARGET"' \
        'echo NO_FURTHER_FEEDBACK > feedback-plan.md' > stub/claude
    chmod +x stub/claude
    PATH="$PWD/stub:$PATH"

    run "$SELF_EDIT_TARGET" -m 1 -e claude -r claude PLAN-x.md

    grep -q CLOBBERED "$SELF_EDIT_TARGET"
    assert_success
    assert_output --partial "Plan Review Loop Complete"
}
