#!/usr/bin/env bats
# Tests for bin/code-review-loop: argument parsing and validation.

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

# =========================================================================
# Run log staging exclusion
#
# stage_review_changes must never offer a run log up as a review change. The
# log directory can sit inside the repo (CODE_REVIEW_LOOP_LOG_DIR allows it),
# and the value can arrive relative, with a trailing slash, or as the project
# root itself, each of which defeated an earlier string-prefix check.
# =========================================================================

# Runs the loop once against a throwaway repo with stub agents, and sets:
#   log_root    absolute path the logs were written under
#   log_count   how many .log files it produced
#   staged_logs how many of them git ended up staging
run_loop_with_logs() { # run_loop_with_logs <CODE_REVIEW_LOOP_LOG_DIR value> <abs log root>
    cd "$BATS_TEST_TMPDIR" || return 1
    rm -rf repo && mkdir repo && cd repo || return 1
    git init -q . && git config user.email t@t && git config user.name t
    echo tracked > f && git add . && git commit -qm init
    echo changed > f && git add f

    mkdir -p stub
    printf '#!/usr/bin/env bash\ncat >/dev/null\necho ran\nprintf "# R\\n\\nHigh: 0\\nMedium: 0\\nLow: 0\\n\\nVerdict: good to go\\n" > agent-code-review.md\n' > stub/claude
    cp stub/claude stub/agy
    chmod +x stub/claude stub/agy
    PATH="$PWD/stub:$PATH"
    # The suite sandboxes HOME, so the installed prompts are not reachable and
    # the loop would exit at validate_prompts before writing a single log.
    # Point at the checkout's own prompts: the test should not depend on
    # whether ./setup has been run on this machine.
    export AI_CODING_SETUP_PROMPTS_DIR="$BATS_TEST_DIRNAME/../prompts"
    export CODE_REVIEW_LOOP_LOG_DIR="$1"

    # Agents named explicitly: without them the reviewer comes from
    # ~/.ai-coding-setup.conf or the built-in default, so the test passes or
    # fails on whether that machine happens to have codex installed. CI does
    # not, and the loop exited at validate_tools before writing a log.
    run "$BATS_TEST_DIRNAME/../bin/code-review-loop" -m 1 -e claude -r claude
    log_root="$2"
    log_count=$(find "$log_root" -name '*.log' -type f 2>/dev/null | wc -l | tr -d ' ')
    staged_logs=$(git diff --staged --name-only | grep -cE '\.log$' || true)
}

@test "run logs are not staged when the log dir is a relative in-repo path" {
    run_loop_with_logs "mylogs" "$BATS_TEST_TMPDIR/repo/mylogs"
    # Assert logs were actually produced, or "none staged" proves nothing.
    [ "$log_count" -gt 0 ]
    [ "$staged_logs" -eq 0 ]
}

@test "run logs are not staged when the log dir has a trailing slash" {
    run_loop_with_logs "$BATS_TEST_TMPDIR/repo/trailing/" "$BATS_TEST_TMPDIR/repo/trailing"
    [ "$log_count" -gt 0 ]
    [ "$staged_logs" -eq 0 ]
}

@test "run logs are not staged when the log dir is the project root" {
    run_loop_with_logs "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/repo"
    [ "$log_count" -gt 0 ]
    [ "$staged_logs" -eq 0 ]
}

@test "each run gets its own log directory under a shared root" {
    run_loop_with_logs "$BATS_TEST_TMPDIR/repo/shared" "$BATS_TEST_TMPDIR/repo/shared"
    [ "$log_count" -gt 0 ]
    git reset -q --hard HEAD
    echo again > f && git add f
    run "$BATS_TEST_DIRNAME/../bin/code-review-loop" -m 1 -e claude -r claude
    # Two runs must not append into one set of step filenames.
    local dirs
    dirs=$(find "$BATS_TEST_TMPDIR/repo/shared" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    [ "$dirs" -eq 2 ]
}
