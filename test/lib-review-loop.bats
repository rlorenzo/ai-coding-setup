#!/usr/bin/env bats
# Unit tests for lib/lib-review-loop: pure library functions.
# Agent runner tests are in test/smoke (uses real CLI agents).

load test_helper

# =========================================================================
# Validation functions
# =========================================================================

@test "validate_agent_name accepts all valid agents" {
    source_lib
    for agent in claude codex copilot antigravity kimi; do
        run validate_agent_name "$agent" "--editor"
        assert_success
    done
}

@test "validate_agent_name rejects unknown agent" {
    source_lib
    run validate_agent_name "gpt4" "--editor"
    assert_failure
    assert_output --partial "Unknown agent"
    assert_output --partial "gpt4"
}

@test "validate_positive_int accepts valid integers" {
    source_lib
    for val in 1 5 100 999; do
        run validate_positive_int "$val" "--max-iterations"
        assert_success
    done
}

@test "validate_positive_int rejects zero" {
    source_lib
    run validate_positive_int "0" "--max-iterations"
    assert_failure
}

@test "validate_positive_int rejects negative numbers" {
    source_lib
    run validate_positive_int "-1" "--max-iterations"
    assert_failure
}

@test "validate_positive_int rejects non-numeric input" {
    source_lib
    run validate_positive_int "abc" "--max-iterations"
    assert_failure
}

@test "validate_positive_int rejects leading-zero numbers" {
    source_lib
    run validate_positive_int "01" "--max-iterations"
    assert_failure
}

@test "validate_prompts succeeds when all files exist" {
    source_lib
    local f1="$TEST_TMPDIR/prompt1.md" f2="$TEST_TMPDIR/prompt2.md"
    touch "$f1" "$f2"
    run validate_prompts "$f1" "$f2"
    assert_success
}

@test "validate_prompts fails when a file is missing" {
    source_lib
    run validate_prompts "/nonexistent/prompt.md"
    assert_failure
    assert_output --partial "Missing prompt files"
}

# =========================================================================
# Prompt loading
# =========================================================================

@test "read_prompt_file strips YAML frontmatter" {
    source_lib
    run read_prompt_file "$PROJECT_ROOT/test/fixtures/prompt-with-frontmatter.md"
    assert_success
    assert_output "Review the code for correctness and clarity."
    refute_output --partial "name:"
    refute_output --partial "---"
}

@test "read_prompt_file returns content unchanged without frontmatter" {
    source_lib
    run read_prompt_file "$PROJECT_ROOT/test/fixtures/prompt-no-frontmatter.md"
    assert_success
    assert_output "Review the code for correctness and clarity."
}

@test "read_prompt_file trims leading and trailing blank lines preserving content" {
    source_lib
    run read_prompt_file "$PROJECT_ROOT/test/fixtures/prompt-blank-lines.md"
    assert_success
    assert_line --index 0 "  Indented content here."
    assert_output --partial "Another line."
    refute_line --index 0 ""
}

# =========================================================================
# Config loading
# =========================================================================

@test "load_config sets agents from config file" {
    source_lib
    cat > "$HOME/.ai-coding-setup.conf" <<'EOF'
EDITOR_AGENT=codex
REVIEWER_AGENT=copilot
EOF
    EDITOR_AGENT=""
    REVIEWER_AGENT=""
    load_config
    assert [ "$EDITOR_AGENT" = "codex" ]
    assert [ "$REVIEWER_AGENT" = "copilot" ]
}

@test "load_config ignores comments and blank lines" {
    source_lib
    cat > "$HOME/.ai-coding-setup.conf" <<'EOF'
# This is a comment
EDITOR_AGENT=codex

# Another comment
REVIEWER_AGENT=claude
EOF
    EDITOR_AGENT=""
    REVIEWER_AGENT=""
    load_config
    assert [ "$EDITOR_AGENT" = "codex" ]
    assert [ "$REVIEWER_AGENT" = "claude" ]
}

@test "load_config strips quotes from values" {
    source_lib
    cat > "$HOME/.ai-coding-setup.conf" <<'EOF'
EDITOR_AGENT="codex"
REVIEWER_AGENT='copilot'
EOF
    EDITOR_AGENT=""
    REVIEWER_AGENT=""
    load_config
    assert [ "$EDITOR_AGENT" = "codex" ]
    assert [ "$REVIEWER_AGENT" = "copilot" ]
}

@test "load_config is no-op when config file missing" {
    source_lib
    EDITOR_AGENT="original"
    REVIEWER_AGENT="original"
    load_config
    assert [ "$EDITOR_AGENT" = "original" ]
    assert [ "$REVIEWER_AGENT" = "original" ]
}

# =========================================================================
# Review status checks
# =========================================================================

@test "test_review_clean returns 0 for 'Verdict: good to go'" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    cp "$PROJECT_ROOT/test/fixtures/review-clean.md" "$REVIEW_FILE"
    run test_review_clean
    assert_success
}

@test "test_review_clean is case-insensitive" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "VERDICT:  GOOD TO GO" > "$REVIEW_FILE"
    run test_review_clean
    assert_success
}

@test "test_review_clean returns 1 for issues present" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    cp "$PROJECT_ROOT/test/fixtures/review-issues.md" "$REVIEW_FILE"
    run test_review_clean
    assert_failure
}

@test "test_review_clean returns 1 when file is missing" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/nonexistent.md"
    run test_review_clean
    assert_failure
}

@test "get_review_issue_counts extracts High/Medium/Low counts" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    cp "$PROJECT_ROOT/test/fixtures/review-issues.md" "$REVIEW_FILE"
    run get_review_issue_counts
    assert_output "High: 2, Medium: 3, Low: 1"
}

@test "get_review_issue_counts shows ? for missing counts" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "High: 1" > "$REVIEW_FILE"
    run get_review_issue_counts
    assert_output "High: 1, Medium: ?, Low: ?"
}

@test "get_review_issue_counts reports no review file" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/nonexistent.md"
    run get_review_issue_counts
    assert_output "No review file"
}

@test "test_reviewer_satisfied returns 0 for NO_FURTHER_FEEDBACK" {
    source_lib
    FEEDBACK_FILE="$TEST_TMPDIR/feedback.md"
    echo "NO_FURTHER_FEEDBACK" > "$FEEDBACK_FILE"
    run test_reviewer_satisfied
    assert_success
}

@test "test_reviewer_satisfied returns 0 with surrounding whitespace" {
    source_lib
    FEEDBACK_FILE="$TEST_TMPDIR/feedback.md"
    printf '  NO_FURTHER_FEEDBACK  \n\n' > "$FEEDBACK_FILE"
    run test_reviewer_satisfied
    assert_success
}

@test "test_reviewer_satisfied returns 1 for feedback with other content" {
    source_lib
    FEEDBACK_FILE="$TEST_TMPDIR/feedback.md"
    printf 'Some feedback here.\nNO_FURTHER_FEEDBACK mentioned in passing.\n' > "$FEEDBACK_FILE"
    run test_reviewer_satisfied
    assert_failure
}

@test "test_reviewer_satisfied returns 1 when file is missing" {
    source_lib
    FEEDBACK_FILE="$TEST_TMPDIR/nonexistent.md"
    run test_reviewer_satisfied
    assert_failure
}

# =========================================================================
# Prompt/detector contract
#
# The loops terminate by grepping for a sentinel the shipped prompt tells the
# agent to emit.  Rewording either side alone breaks the loop silently, so
# feed each prompt's own sentinel to the detector that looks for it.
# =========================================================================

@test "code-review prompt states the verdict test_review_clean detects" {
    source_lib
    verdict=$(grep -m1 -o '\*\*Verdict:[^*]*\*\*' "$PROJECT_ROOT/prompts/code-review.md") \
        || fail "prompts/code-review.md no longer states a **Verdict: ...** line"
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "$verdict" > "$REVIEW_FILE"
    run test_review_clean
    assert_success
}

@test "plan-review prompt states the sentinel test_reviewer_satisfied detects" {
    source_lib
    grep -qF 'NO_FURTHER_FEEDBACK' "$PROJECT_ROOT/prompts/plan-review.md" \
        || fail "prompts/plan-review.md no longer names the NO_FURTHER_FEEDBACK sentinel"
    FEEDBACK_FILE="$TEST_TMPDIR/feedback.md"
    echo "NO_FURTHER_FEEDBACK" > "$FEEDBACK_FILE"
    run test_reviewer_satisfied
    assert_success
}

@test "test_review_clean accepts the verdict as a Summary bullet" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "- **Verdict: good to go**" > "$REVIEW_FILE"
    run test_review_clean
    assert_success
}

@test "test_review_clean rejects a verdict hedged with trailing prose" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "**Verdict: good to go, but 3 High findings remain**" > "$REVIEW_FILE"
    run test_review_clean
    assert_failure
}

@test "test_review_clean accepts a verdict with a trailing period" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "**Verdict: good to go**." > "$REVIEW_FILE"
    run test_review_clean
    assert_success
}

@test "test_review_clean ignores a verdict quoted inside prose" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "The loop stops once the report says Verdict: good to go." > "$REVIEW_FILE"
    run test_review_clean
    assert_failure
}

# The prompts ask the reviewer to state the verdict "in the Summary", and agents
# oblige by ending the summary paragraph with it.  Requiring a line of its own
# made every such review read as unclean: the loop then burned all five cycles on
# an already-clean diff and reported MAX ITERATIONS REACHED.
@test "test_review_clean accepts a verdict closing a summary paragraph" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "The suite passes and linters are clean. Finding counts: High 0, Medium 0, Low 0. **Verdict: good to go**." > "$REVIEW_FILE"
    run test_review_clean
    assert_success
}

@test "test_review_clean accepts a verdict after a sentence on a heading line" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "## Verdict: good to go" > "$REVIEW_FILE"
    run test_review_clean
    assert_success
}

@test "test_review_clean rejects a paragraph verdict hedged with trailing prose" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "All checks ran. **Verdict: good to go, but 2 High findings remain**." > "$REVIEW_FILE"
    run test_review_clean
    assert_failure
}

@test "test_review_clean still ignores a mid-sentence verdict after a period" {
    source_lib
    REVIEW_FILE="$TEST_TMPDIR/review.md"
    echo "Re-run it. The report will say Verdict: good to go." > "$REVIEW_FILE"
    run test_review_clean
    assert_failure
}

@test "build_improvement_prompt includes all parameters" {
    source_lib
    run build_improvement_prompt "/path/to/plan.md" "/path/to/feedback.md" "codex" "2" "5"
    assert_success
    assert_output --partial "/path/to/plan.md"
    assert_output --partial "/path/to/feedback.md"
    assert_output --partial "cycle 2 of 5"
    assert_output --partial "codex"
}

# =========================================================================
# Utility functions
# =========================================================================

@test "format_elapsed computes minutes and seconds" {
    source_lib
    local now
    now=$(date +%s)
    run format_elapsed $(( now - 125 ))
    # Allow for 1-second clock skew between date calls
    assert_output --regexp "^2m [56]s$"
}

# =========================================================================
# Agent output logging
#
# run_agent dispatches to a real CLI, so these stub one onto PATH and assert
# only the wrapper's own behaviour: that it mirrors output, and that it hands
# back the agent's exit code rather than tee's.
# =========================================================================

stub_agent() { # stub_agent <exit-code> <stdout-line> [stderr-line]
    local dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$dir"
    {
        echo '#!/usr/bin/env bash'
        echo 'cat >/dev/null'
        printf 'echo %q\n' "$2"
        [ -n "${3:-}" ] && printf 'echo %q >&2\n' "$3"
        echo "exit $1"
    } > "$dir/claude"
    chmod +x "$dir/claude"
    PATH="$dir:$PATH"
}

@test "run_agent without AGENT_LOG passes output through and writes no file" {
    source_lib
    stub_agent 0 "refined the code"
    unset AGENT_LOG
    run run_agent claude "a prompt" "Read"
    assert_success
    assert_output --partial "refined the code"
    [ -z "$(find "$BATS_TEST_TMPDIR" -name '*.log' -print -quit)" ]
}

@test "run_agent mirrors output to AGENT_LOG and records the exit code" {
    source_lib
    stub_agent 0 "refined the code"
    AGENT_LOG="$BATS_TEST_TMPDIR/logs/step.log" run run_agent claude "a prompt" "Read"
    assert_success
    assert_output --partial "refined the code"
    run cat "$BATS_TEST_TMPDIR/logs/step.log"
    assert_output --partial "agent=claude"
    assert_output --partial "refined the code"
    assert_output --partial "exit=0"
}

@test "run_agent returns the agent's exit code, not tee's" {
    source_lib
    stub_agent 1 "partial work" "Execution error"
    AGENT_LOG="$BATS_TEST_TMPDIR/logs/step.log" run run_agent claude "a prompt" "Read"
    assert_failure
    # The caller's `|| local_exit=$?` depends on this, and tee always succeeds.
    [ "$status" -eq 1 ]
}

@test "run_agent captures a failing agent's stderr in the log" {
    source_lib
    stub_agent 1 "partial work" "Execution error"
    AGENT_LOG="$BATS_TEST_TMPDIR/logs/step.log" run run_agent claude "a prompt" "Read"
    run cat "$BATS_TEST_TMPDIR/logs/step.log"
    # The whole point: a run that dies leaves the reason on disk.
    assert_output --partial "Execution error"
    assert_output --partial "exit=1"
}

@test "run_agent creates the log directory if it does not exist" {
    source_lib
    stub_agent 0 "ok"
    AGENT_LOG="$BATS_TEST_TMPDIR/deep/nested/dir/step.log" run run_agent claude "p" "Read"
    assert_success
    [ -f "$BATS_TEST_TMPDIR/deep/nested/dir/step.log" ]
}

# =========================================================================
# Run log retention
# =========================================================================

make_run_dir() { # make_run_dir <root> <name> <days-old>
    local dir="$1/$2"
    mkdir -p "$dir"
    echo "log" > "$dir/step.log"
    if [ "$3" -gt 0 ]; then
        # touch -A/-d differ across platforms; -t with a computed stamp is portable.
        local stamp
        stamp=$(date -v "-$3d" '+%Y%m%d%H%M' 2>/dev/null) \
            || stamp=$(date -d "$3 days ago" '+%Y%m%d%H%M')
        touch -t "$stamp" "$dir"
    fi
}

@test "prune_run_logs also deletes a suffixed run directory" {
    source_lib
    local root="$BATS_TEST_TMPDIR/logs"
    # A run that lost the claim race is named <stamp>-XXXXXX and must not
    # outlive the plain ones just because of its suffix.
    make_run_dir "$root" 20260101-120000-a1b2c3 5
    make_run_dir "$root" 20260807-120000-d4e5f6 0
    run prune_run_logs "$root"
    assert_output "1"
    [ ! -d "$root/20260101-120000-a1b2c3" ]
    [ -d "$root/20260807-120000-d4e5f6" ]
}

@test "prune_run_logs deletes runs older than a day and keeps today's" {
    source_lib
    local root="$BATS_TEST_TMPDIR/logs"
    make_run_dir "$root" 20260101-120000 5
    make_run_dir "$root" 20260102-120000 3
    make_run_dir "$root" 20260807-120000 0
    run prune_run_logs "$root"
    assert_output "2"
    [ ! -d "$root/20260101-120000" ]
    [ ! -d "$root/20260102-120000" ]
    [ -d "$root/20260807-120000" ]
}

@test "prune_run_logs leaves everything when nothing is old enough" {
    source_lib
    local root="$BATS_TEST_TMPDIR/logs"
    make_run_dir "$root" 20260807-120000 0
    make_run_dir "$root" 20260807-130000 0
    run prune_run_logs "$root"
    assert_output ""
    [ -d "$root/20260807-120000" ]
    [ -d "$root/20260807-130000" ]
}

@test "prune_run_logs ignores directories that are not run stamps" {
    source_lib
    local root="$BATS_TEST_TMPDIR/logs"
    mkdir -p "$root/backups" "$root/notes"
    echo keep > "$root/backups/original.sh"
    touch -t 202001010000 "$root/backups" "$root/notes"
    make_run_dir "$root" 20260101-120000 5
    run prune_run_logs "$root"
    assert_output "1"
    # Anything a user keeps alongside the run dirs is not ours to delete.
    [ -f "$root/backups/original.sh" ]
    [ -d "$root/notes" ]
}

@test "prune_run_logs honours a custom retention in days" {
    source_lib
    local root="$BATS_TEST_TMPDIR/logs"
    make_run_dir "$root" 20260101-120000 10
    make_run_dir "$root" 20260102-120000 3
    run prune_run_logs "$root" 7
    assert_output "1"
    [ ! -d "$root/20260101-120000" ]
    [ -d "$root/20260102-120000" ]
}

@test "prune_run_logs is a no-op on a missing or invalid target" {
    source_lib
    run prune_run_logs "$BATS_TEST_TMPDIR/nope"
    assert_success
    assert_output ""
    local root="$BATS_TEST_TMPDIR/logs"
    make_run_dir "$root" 20260101-120000 5
    run prune_run_logs "$root" "not-a-number"
    assert_output ""
    [ -d "$root/20260101-120000" ]
}

@test "cleanup_agent_artifacts does not delete run logs inside the repo" {
    source_lib
    cd "$BATS_TEST_TMPDIR"
    git init -q . && git config user.email t@t && git config user.name t
    echo tracked > kept.txt && git add . && git commit -qm init

    RUN_LOG_DIR="$BATS_TEST_TMPDIR/logs/20260807-120000"
    mkdir -p "$RUN_LOG_DIR"

    local before="$BATS_TEST_TMPDIR/before.txt"
    snapshot_untracked > "$before"

    # Both appear during the run: one is a Codex artifact, one is our own log.
    echo junk > artifact.txt
    echo "agent output" > "$RUN_LOG_DIR/3-review.codex.log"

    run cleanup_agent_artifacts codex "$before" reviewer
    assert_success
    [ ! -f artifact.txt ]
    [ -f "$RUN_LOG_DIR/3-review.codex.log" ]
}

@test "claim_run_log_dir gives concurrent callers separate directories" {
    source_lib
    local root="$BATS_TEST_TMPDIR/logs"
    local out="$BATS_TEST_TMPDIR/claimed.txt"
    : > "$out"

    # Twenty at once, all inside the same second, which is exactly when a
    # check-then-create claim hands two callers the same name.
    local _
    for _ in $(seq 1 20); do
        ( claim_run_log_dir "$root" >> "$out" ) &
    done
    wait

    local claimed unique
    claimed=$(wc -l < "$out" | tr -d ' ')
    unique=$(sort -u "$out" | wc -l | tr -d ' ')
    [ "$claimed" -eq 20 ]
    [ "$unique" -eq 20 ]
}

@test "claim_run_log_dir creates the root when it is missing" {
    source_lib
    local dir
    dir=$(claim_run_log_dir "$BATS_TEST_TMPDIR/deep/nested/root")
    [ -d "$dir" ]
    [[ "$dir" == "$BATS_TEST_TMPDIR/deep/nested/root/"* ]]
}

@test "is_inside_dir resolves relative and trailing-slash paths" {
    source_lib
    local root="$BATS_TEST_TMPDIR/root"
    mkdir -p "$root/logs" "$root/other"
    : > "$root/logs/a.log"
    : > "$root/other/b.txt"
    cd "$root" || return 1

    run is_inside_dir "logs/a.log" "logs";      assert_success
    run is_inside_dir "logs/a.log" "logs/";     assert_success
    run is_inside_dir "logs/a.log" "$root/logs"; assert_success
    run is_inside_dir "other/b.txt" "logs";     assert_failure
    # An empty or missing directory is never a container.
    run is_inside_dir "logs/a.log" "";          assert_failure
    run is_inside_dir "logs/a.log" "$root/nope"; assert_failure
}

# Split out, because Git Bash copies rather than links unless Developer Mode is
# on, which leaves no symlink to resolve. Detected by trying, not by testing the
# platform name: a Windows box that can make real symlinks should still run it.
@test "is_inside_dir resolves a symlinked directory" {
    source_lib
    local root="$BATS_TEST_TMPDIR/root"
    mkdir -p "$root/logs"
    : > "$root/logs/a.log"
    ln -s "$root/logs" "$root/linked" 2>/dev/null || true
    [ -L "$root/linked" ] || skip "no real symlink support here"
    cd "$root" || return 1

    run is_inside_dir "logs/a.log" "linked";    assert_success
}

# =========================================================================
# Codex invocation
#
# The flags run_codex passes are a compatibility surface, not an internal
# detail: codex rejects an unknown flag at parse time, so a stale one means
# the agent never starts and the loop ends with no review written. That
# failure looked like a codex problem rather than ours, so pin the contract.
# =========================================================================

stub_codex() { # records the argv it was invoked with, then succeeds
    local dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$dir"
    {
        echo '#!/usr/bin/env bash'
        echo 'cat >/dev/null'
        printf 'printf "%%s\\n" "$@" > %q\n' "$BATS_TEST_TMPDIR/codex-argv"
    } > "$dir/codex"
    chmod +x "$dir/codex"
    PATH="$dir:$PATH"
}

@test "run_codex does not pass --full-auto, which codex exec no longer accepts" {
    source_lib
    stub_codex
    run run_agent codex "a prompt" "Read"
    assert_success
    run cat "$BATS_TEST_TMPDIR/codex-argv"
    refute_output --partial "--full-auto"
}

@test "run_codex requests a sandbox that can write the review file" {
    source_lib
    stub_codex
    run run_agent codex "a prompt" "Read"
    assert_success
    run cat "$BATS_TEST_TMPDIR/codex-argv"
    # read-only would let the agent run but silently fail to write
    # agent-code-review.md, which the loop reports as a dead codex.
    assert_output --partial "--sandbox"
    assert_output --partial "workspace-write"
}

@test "run_codex still runs exec non-interactively with MCP servers disabled" {
    source_lib
    stub_codex
    run run_agent codex "a prompt" "Read"
    assert_success
    run cat "$BATS_TEST_TMPDIR/codex-argv"
    assert_output --partial "exec"
    assert_output --partial "mcp_servers={}"
    # The trailing "-" is what makes codex read the prompt from stdin.
    # assert_line matches a whole argument: --partial would also be satisfied
    # by the hyphens in --sandbox, so it would pass with the "-" removed.
    assert_line "-"
}
