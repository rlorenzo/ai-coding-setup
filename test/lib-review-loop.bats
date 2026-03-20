#!/usr/bin/env bats
# Unit tests for lib/lib-review-loop — pure library functions.
# Agent runner tests are in test/smoke (uses real CLI agents).

load test_helper

# =========================================================================
# Validation functions
# =========================================================================

@test "validate_agent_name accepts all valid agents" {
    source_lib
    for agent in claude codex gemini copilot; do
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
EDITOR_AGENT=gemini
REVIEWER_AGENT=copilot
EOF
    EDITOR_AGENT=""
    REVIEWER_AGENT=""
    load_config
    assert [ "$EDITOR_AGENT" = "gemini" ]
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
REVIEWER_AGENT='gemini'
EOF
    EDITOR_AGENT=""
    REVIEWER_AGENT=""
    load_config
    assert [ "$EDITOR_AGENT" = "codex" ]
    assert [ "$REVIEWER_AGENT" = "gemini" ]
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
    local start
    start=$(( $(date +%s) - 125 ))
    run format_elapsed "$start"
    assert_output "2m 5s"
}
