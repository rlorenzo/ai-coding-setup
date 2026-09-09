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

# Creates a throwaway git repo under $BATS_TEST_TMPDIR with one staged change
# and leaves the shell inside it.
init_staged_repo() { # init_staged_repo <dir name>
    cd "$BATS_TEST_TMPDIR" || return 1
    mkdir -p "$1" && cd "$1" || return 1
    git init -q . && git config user.email t@t && git config user.name t
    echo tracked > f && git add . && git commit -qm init
    echo changed > f && git add f
}

# Puts a stub agent on PATH in $PWD/stub. It swallows the prompt on stdin and
# writes the clean verdict the loop parses, so that payload has one home to
# keep in step with test_reviewer_satisfied. $1 injects extra stub body.
write_stub_agent() { # write_stub_agent [extra shell to run inside the stub]
    mkdir -p stub
    {
        printf '#!/usr/bin/env bash\ncat >/dev/null\n'
        printf '%s\n' "${1:-:}"
        printf 'echo ran\n'
        printf 'printf "# R\\n\\nHigh: 0\\nMedium: 0\\nLow: 0\\n\\nVerdict: good to go\\n" > agent-code-review.md\n'
    } > stub/claude
    cp stub/claude stub/agy
    chmod +x stub/claude stub/agy
    PATH="$PWD/stub:$PATH"
}

# Runs the loop once against a throwaway repo with stub agents, and sets:
#   log_root    absolute path the logs were written under
#   log_count   how many .log files it produced
#   staged_logs how many of them git ended up staging
run_loop_with_logs() { # run_loop_with_logs <CODE_REVIEW_LOOP_LOG_DIR value> <abs log root>
    init_staged_repo repo
    write_stub_agent
    # The suite sandboxes HOME, so the installed prompts are not reachable and
    # the loop would exit at validate_prompts before writing a single log.
    # Point at the checkout's own prompts: the test should not depend on
    # whether ./setup has been run on this machine.
    export AI_CODING_SETUP_PROMPTS_DIR="$PROJECT_ROOT/prompts"
    export CODE_REVIEW_LOOP_LOG_DIR="$1"

    # Agents named explicitly: without them the reviewer comes from
    # ~/.ai-coding-setup.conf or the built-in default, so the test passes or
    # fails on whether that machine happens to have codex installed. CI does
    # not, and the loop exited at validate_tools before writing a log.
    run "$BIN" -m 1 -e claude -r claude
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
    run "$BIN" -m 1 -e claude -r claude
    # Two runs must not append into one set of step filenames.
    local dirs
    dirs=$(find "$BATS_TEST_TMPDIR/repo/shared" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    [ "$dirs" -eq 2 ]
}

# =========================================================================
# Tool allowlist per step
#
# The refinement prompt fans its angles out to subagents, so that step alone
# needs the subagent tool. Every other step reuses EDITOR_TOOLS without it.
# =========================================================================

@test "only the refinement step allowlists the subagent tool" {
    run_loop_with_logs "$BATS_TEST_TMPDIR/repo/tools" "$BATS_TEST_TMPDIR/repo/tools"
    [ "$log_count" -gt 0 ]

    local refinement review
    refinement=$(find "$log_root" -name '1-refinement.*.log' -type f)
    review=$(find "$log_root" -name '3-review-initial.*.log' -type f)
    [ -n "$refinement" ]
    [ -n "$review" ]

    # run_agent writes a `tools=` header per invocation.
    grep -q '^=== .*tools=.*,Task,Agent ===$' "$refinement"
    run grep -q 'Task,Agent' "$review"
    assert_failure
}

# =========================================================================
# Self-edit resilience
#
# The loop hands editor agents a working tree holding the loop script itself.
# Bash reads a script by byte offset, so a mid-run rewrite used to kill it
# mid-token or stop it silently. The script's brace group parses it up front.
# =========================================================================

@test "the loop survives an agent rewriting the script mid-run" {
    # Mirror the installed layout: the copy finds lib/, the checkout is safe.
    mkdir -p "$BATS_TEST_TMPDIR/install/bin" "$BATS_TEST_TMPDIR/install/lib"
    cp "$BIN" "$BATS_TEST_TMPDIR/install/bin/code-review-loop"
    cp "$PROJECT_ROOT/lib/lib-review-loop" "$BATS_TEST_TMPDIR/install/lib/lib-review-loop"
    chmod +x "$BATS_TEST_TMPDIR/install/bin/code-review-loop"
    export SELF_EDIT_TARGET="$BATS_TEST_TMPDIR/install/bin/code-review-loop"

    init_staged_repo repo
    # Clobber the running script the way a refinement agent does. Truncate in
    # place, never rename: a rename leaves bash on the original inode and the
    # test passes vacuously. Single quotes defer $SELF_EDIT_TARGET to run time.
    # shellcheck disable=SC2016
    write_stub_agent 'printf "#!/usr/bin/env bash\\necho CLOBBERED\\n" > "$SELF_EDIT_TARGET"'
    export AI_CODING_SETUP_PROMPTS_DIR="$PROJECT_ROOT/prompts"
    export CODE_REVIEW_LOOP_LOG_DIR="$BATS_TEST_TMPDIR/logs"

    run "$SELF_EDIT_TARGET" -m 1 -e claude -r claude

    # The script really was clobbered, or the test proves nothing.
    grep -q CLOBBERED "$SELF_EDIT_TARGET"
    # ...and the run still reached the end instead of stopping at the rewrite.
    assert_success
    assert_output --partial "Review Loop Complete"
}
