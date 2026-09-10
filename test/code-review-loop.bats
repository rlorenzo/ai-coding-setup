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
    # -b main so the branch-scope tests below get a predictable default branch
    # instead of whatever init.defaultBranch this machine happens to set.
    git init -q -b main . && git config user.email t@t && git config user.name t
    echo tracked > f && git add . && git commit -qm init
    echo changed > f && git add f
}

# Puts a stub agent on PATH in $PWD/stub. It swallows the prompt on stdin and
# writes the clean verdict the loop parses, so that payload has one home to
# keep in step with test_reviewer_satisfied. $1 injects extra stub body.
# Set STUB_PROMPT_LOG first to keep the prompts instead of dropping them.
write_stub_agent() { # write_stub_agent [extra shell to run inside the stub]
    mkdir -p stub
    {
        printf '#!/usr/bin/env bash\ncat >> "%s"\n' "${STUB_PROMPT_LOG:-/dev/null}"
        printf '%s\n' "${1:-:}"
        printf 'echo ran\n'
        printf 'printf "# R\\n\\nHigh: 0\\nMedium: 0\\nLow: 0\\n\\nVerdict: good to go\\n" > agent-code-review.md\n'
    } > stub/claude
    cp stub/claude stub/agy
    chmod +x stub/claude stub/agy
    PATH="$PWD/stub:$PATH"
}

# Every test here needs both of these. The suite sandboxes HOME, so the
# installed prompts are not reachable and the loop would exit at
# validate_prompts before doing anything; point at the checkout's own prompts
# so the test does not depend on whether ./setup has been run on this machine.
# The log dir is named too, to keep runs out of ~/.cache.
use_checkout_prompts() { # use_checkout_prompts [CODE_REVIEW_LOOP_LOG_DIR value]
    export AI_CODING_SETUP_PROMPTS_DIR="$PROJECT_ROOT/prompts"
    export CODE_REVIEW_LOOP_LOG_DIR="${1:-$BATS_TEST_TMPDIR/logs}"
}

# Runs the loop once against a throwaway repo with stub agents, and sets:
#   log_root    absolute path the logs were written under
#   log_count   how many .log files it produced
#   staged_logs how many of them git ended up staging
run_loop_with_logs() { # run_loop_with_logs <CODE_REVIEW_LOOP_LOG_DIR value> <abs log root>
    init_staged_repo repo
    write_stub_agent
    use_checkout_prompts "$1"

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
    use_checkout_prompts

    run "$SELF_EDIT_TARGET" -m 1 -e claude -r claude

    # The script really was clobbered, or the test proves nothing.
    grep -q CLOBBERED "$SELF_EDIT_TARGET"
    # ...and the run still reached the end instead of stopping at the rewrite.
    assert_success
    assert_output --partial "Review Loop Complete"
}

# =========================================================================
# --branch: branch commits join the review scope
#
# Without --branch, a branch whose work is already committed has nothing staged
# and the loop exits before reviewing. With --branch REF the diff is taken
# against the merge-base, so those commits are reviewed and the agents are
# told which diff command to read.
# =========================================================================

# A repo on a feature branch with one commit past main and a clean index:
# init_staged_repo's staged change, committed on the branch instead.
init_branch_repo() { # init_branch_repo <dir name>
    init_staged_repo "$1" || return 1
    git checkout -qb feature
    git commit -qam work
}

@test "without --branch, committed branch work is out of scope" {
    init_branch_repo repo
    write_stub_agent
    use_checkout_prompts
    run "$BIN" -s -m 1 -e claude -r claude
    assert_success
    assert_output --partial "No changes to review"
}

@test "--branch reviews the branch's commits and tells agents the diff command" {
    init_branch_repo repo
    # Keep the prompts the stub is given, so the scope note is observable.
    export STUB_PROMPT_LOG="$BATS_TEST_TMPDIR/prompts.txt"
    write_stub_agent
    use_checkout_prompts
    run "$BIN" -s -m 1 -e claude -r claude --branch main
    assert_success
    assert_output --partial "Scope          : branch since main"
    assert_output --partial "Review Loop Complete"
    local mb
    mb=$(git merge-base main HEAD)
    grep -q "git diff --staged $mb" "$BATS_TEST_TMPDIR/prompts.txt"
    # Fixes stay staged, never committed.
    [ "$(git rev-list --count main..HEAD)" -eq 1 ]
}

@test "bare --branch detects the default branch" {
    init_branch_repo repo
    write_stub_agent
    use_checkout_prompts
    # The flag after --branch must not be swallowed as the ref.
    run "$BIN" -s -e claude -r claude --branch -m 1
    assert_success
    assert_output --partial "Scope          : branch since main"
    assert_output --partial "Max iterations : 1"
}

@test "bare --branch prefers origin/HEAD over the main fallback" {
    init_branch_repo repo
    # A tracking ref pointing somewhere other than main, so passing this
    # assertion cannot happen by way of the main/master fallback.
    git branch -q trunk main
    git update-ref refs/remotes/origin/trunk "$(git rev-parse trunk)"
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
    write_stub_agent
    use_checkout_prompts
    run "$BIN" -s -m 1 -e claude -r claude --branch
    assert_success
    assert_output --partial "Scope          : branch since origin/trunk"
}

@test "bare --branch errors when no default branch can be found" {
    cd "$BATS_TEST_TMPDIR" || return 1
    mkdir -p solo && cd solo || return 1
    # No origin, and the branch is neither main nor master.
    git init -q -b trunk . && git config user.email t@t && git config user.name t
    echo tracked > f && git add . && git commit -qm init
    write_stub_agent
    use_checkout_prompts
    run "$BIN" -s -e claude -r claude --branch
    assert_failure
    assert_output --partial "could not detect the default branch"
}

@test "--branch with an unknown ref fails before running any agent" {
    init_branch_repo repo
    write_stub_agent
    use_checkout_prompts
    run "$BIN" -s -e claude -r claude --branch nope
    assert_failure
    assert_output --partial "no merge-base"
}

@test "--branch rejects unstaged edits to a committed branch file" {
    init_branch_repo repo
    # Nothing staged, so the index-only check saw a clean tree; the file is in
    # scope through the branch's commit, and its fixes would never be staged.
    echo more >> f
    write_stub_agent
    use_checkout_prompts
    run "$BIN" -s -e claude -r claude --branch main
    assert_failure
    assert_output --partial "files in the review scope have unstaged changes"
    assert_output --partial "  f"
}

@test "--branch rejects a staged revert to the merge-base with a later edit" {
    init_branch_repo repo
    # Staged content matches main, so the branch diff is empty for f; only the
    # index still lists it, and the staging step would git add the stray edit.
    echo tracked > f && git add f
    echo stray >> f
    write_stub_agent
    use_checkout_prompts
    run "$BIN" -s -e claude -r claude --branch main
    assert_failure
    assert_output --partial "files in the review scope have unstaged changes"
    assert_output --partial "  f"
    run git show :f
    assert_output "tracked"
    run cat f
    assert_output $'tracked\nstray'
}

@test "--branch stages agent fixes to clean committed branch files" {
    init_branch_repo repo
    write_stub_agent 'echo fixed >> f'
    use_checkout_prompts
    # Refinement runs, so the staging step follows an agent that edited f.
    run "$BIN" -m 1 -e claude -r claude --branch main
    assert_success
    git diff --staged --name-only | grep -qx f
}
