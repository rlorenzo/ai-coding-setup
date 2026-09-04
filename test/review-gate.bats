#!/usr/bin/env bats
# Tests for bin/review-gate: the code review gate. It is a harness PreToolUse
# hook, not a git pre-commit hook, which matters when working out why it ran.
#
# All of the gate's logic is git plumbing and string parsing, so the whole
# decision tree is reachable without invoking a single agent.
#
# A `@test "..." { ... }` body reads to the linter as a subshell, so every
# variable a test exports and then reads back looks like a modification that
# gets lost. bats runs each body in its own process by design; that is exactly
# the isolation these tests rely on.
#
# SC2016 is off for the same kind of reason: the PowerShell cases pass
# `$env:...` through as literal text for the gate to parse, so expanding it
# here is exactly what must not happen.
# shellcheck disable=SC2030,SC2031,SC2016

load test_helper

GATE="$PROJECT_ROOT/bin/review-gate"

# ---- fixtures -------------------------------------------------------------

# Create a throwaway repo at $REPO with one commit, and stage nothing.
mkrepo() {
    REPO="$TEST_TMPDIR/repo"
    rm -rf "$REPO"
    mkdir -p "$REPO"
    git -C "$REPO" init -q .
    git -C "$REPO" config user.email t@t
    git -C "$REPO" config user.name t
    echo base > "$REPO/base.txt"
    git -C "$REPO" add base.txt
    git -C "$REPO" commit -qm init
}

# Create a throwaway repo at $REPO with no commits at all.
mkrepo_unborn() {
    REPO="$TEST_TMPDIR/repo"
    rm -rf "$REPO"
    mkdir -p "$REPO"
    git -C "$REPO" init -q .
    git -C "$REPO" config user.email t@t
    git -C "$REPO" config user.name t
}

# Stage a code change, so the gate has something to refuse.
stage_code() {
    echo "def f(): return 1" > "$REPO/app.py"
    git -C "$REPO" add app.py
}

# Feed one command through the gate as the harness would.
gate() { # gate <command>
    # jq is a native Windows binary under Git Bash, and MSYS rewrites any
    # argument that looks like a POSIX path on the way to one. Without these,
    # `--arg c '/usr/bin/git commit'` reaches jq as the Git installation's own
    # path, which on a runner is `C:/Program Files/Git/usr/bin/git` and
    # tokenizes into two words, testing something nobody wrote. Both variables
    # are inert off Windows.
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
    jq -nc --arg c "$1" --arg cwd "$REPO" --arg tool "${GATE_TOOL:-Bash}" \
        '{tool_name: $tool, tool_input: {command: $c}, cwd: $cwd}' \
        | "$GATE" "--format=${GATE_FORMAT:-claude}"
}

# Feed one command through the gate as the Windows PowerShell tool would.
# Windows harnesses expose that tool alongside Bash, and it takes incompatible
# syntax for the bypass the gate hands back.
ps_gate() { # ps_gate <command>
    GATE_TOOL=PowerShell gate "$1"
}

state_dir() { printf '%s\n' "$REPO/.git/ai-review"; }

# Record a receipt through the library helper the review loop uses.
write_receipt() { # write_receipt <verdict>
    (
        cd "$REPO" || exit 1
        source_lib
        write_review_receipt "$1" 1 claude codex
    )
}

# Pull the nonce out of a deny reason.
nonce_from_output() {
    printf '%s' "$output" | grep -o 'AI_REVIEW_GATE=[0-9a-f]\{4,\}' | head -1 | cut -d= -f2
}

# Same, from the PowerShell statement form the gate emits for that tool.
ps_nonce_from_output() {
    printf '%s' "$output" \
        | grep -o '\$env:AI_REVIEW_GATE = \\"[0-9a-f]\{4,\}\\"' \
        | head -1 | grep -o '[0-9a-f]\{4,\}'
}

assert_allowed() {
    assert_success
    assert_output ""
}

assert_denied() {
    assert_success
    assert_output --partial '"permissionDecision":"deny"'
}

assert_warned() {
    assert_success
    assert_output --partial 'Code review gate'
    refute_output --partial '"permissionDecision":"deny"'
}

# Blocking is the interesting mode; the shipped default is warn.
setup_gate() {
    export REVIEW_GATE=block
    unset AI_REVIEW_GATE AI_REVIEW_HEADLESS CI GATE_FORMAT
}

# =========================================================================
# The infinite-loop test, first.
#
# A PreToolUse hook is spawned by the harness before the shell runs the
# command, so an inline `AI_REVIEW_GATE=<nonce> git commit ...` assignment
# never reaches the hook's own environment. Reading it from the environment
# instead of the command string is the single most likely way to ship a gate
# that denies the agent's retry forever.
# =========================================================================

@test "nonce is read from an inline assignment in the command string" {
    setup_gate; mkrepo; stage_code

    run gate 'git commit -m "add app"'
    assert_denied
    local n
    n=$(nonce_from_output)
    [ -n "$n" ]

    # The hook's own environment carries no nonce; only the command does.
    run env -u AI_REVIEW_GATE bash -c \
        "REVIEW_GATE=block; export REVIEW_GATE; jq -nc --arg c 'AI_REVIEW_GATE=$n git commit -m \"add app\"' --arg cwd '$REPO' '{tool_input:{command:\$c},cwd:\$cwd}' | '$GATE'"
    assert_allowed
}

@test "nonce is single-use" {
    setup_gate; mkrepo; stage_code

    run gate 'git commit -m "add app"'
    assert_denied
    local n
    n=$(nonce_from_output)

    run gate "AI_REVIEW_GATE=$n git commit -m \"add app\""
    assert_allowed

    run gate "AI_REVIEW_GATE=$n git commit -m \"add app\""
    assert_denied
}

@test "nonce is rejected for a different index tree" {
    setup_gate; mkrepo; stage_code

    run gate 'git commit -m "add app"'
    assert_denied
    local n
    n=$(nonce_from_output)

    # Staging more work moves the index out from under the nonce.
    echo more > "$REPO/other.py"
    git -C "$REPO" add other.py

    run gate "AI_REVIEW_GATE=$n git commit -m \"add app\""
    assert_denied
}

# =========================================================================
# Command detection
# =========================================================================

@test "plain git commit is detected" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit -m "add app"'
    assert_denied
}

# A wrapper or a decorated command word must not be a way past the gate. Each
# of these is an ordinary commit that an agent can type without trying, and
# every one of them was allowed before.

@test "git.exe is detected" {
    setup_gate; mkrepo; stage_code
    run gate 'git.exe commit -m "add app"'
    assert_denied
}

@test "a git.exe command word is matched case-insensitively" {
    setup_gate; mkrepo; stage_code
    run gate 'GIT.EXE commit -m "add app"'
    assert_denied
}

@test "an absolute path to git is detected" {
    setup_gate; mkrepo; stage_code
    run gate '/usr/bin/git commit -m "add app"'
    assert_denied
}

@test "a Windows path to git.exe is detected under PowerShell" {
    setup_gate; mkrepo; stage_code
    # A backslash is a path character there, not an escape. Folding it away
    # turns the command word into something unrecognizable and lets it past.
    run ps_gate '& "C:\Program Files\Git\bin\git.exe" commit -m "add app"'
    assert_denied
}

@test "env -i git commit is detected" {
    setup_gate; mkrepo; stage_code
    run gate 'env -i git commit -m "add app"'
    assert_denied
}

@test "env -u NAME git commit is detected" {
    setup_gate; mkrepo; stage_code
    run gate 'env -u FOO git commit -m "add app"'
    assert_denied
}

@test "env --split-string carrying a commit is detected" {
    setup_gate; mkrepo; stage_code
    # -S packs a whole command into one argument. Skipping that argument steps
    # straight over the commit.
    run gate 'env -S "git commit -m x"'
    assert_denied
    run gate 'env --split-string="git commit -m x"'
    assert_denied
}

@test "staging flags inside an env --split-string are still read" {
    setup_gate; mkrepo; stage_code
    run gate 'env -S "git commit -am x"'
    assert_denied
    assert_output --partial 'beyond the index'
}

@test "operands after an env --split-string belong to the same command" {
    setup_gate; mkrepo; stage_code
    # env appends them to the command it builds, so `env -S "git" commit` is a
    # commit and dropping the tail loses it entirely.
    run gate 'env -S "git" commit -m x'
    assert_denied
}

@test "a staging flag after an env --split-string is still read" {
    setup_gate; mkrepo; stage_code
    # Losing this one is worse than losing the commit: the gate would let a
    # receipt describing the index vouch for a working-tree commit.
    run gate 'env -S "git commit" -a -m x'
    assert_denied
    assert_output --partial 'beyond the index'
}

@test "a spaced message survives the split-string path intact" {
    setup_gate; mkrepo; stage_code
    # If the token arrays were expanded unquoted anywhere on this path, the
    # message would split and its fragments would read as pathspecs, which the
    # gate reports as committing beyond the index. Absence of that is the
    # assertion: the message stayed one token.
    run gate 'env -S "git commit" -m "one two three four"'
    assert_denied
    refute_output --partial 'beyond the index'
}

@test "env --split-string without a commit still allows" {
    setup_gate; mkrepo; stage_code
    run gate 'env -S "ls -la"'
    assert_allowed
}

@test "command and sudo wrappers are detected" {
    setup_gate; mkrepo; stage_code
    run gate 'command git commit -m "add app"'
    assert_denied
    run gate 'sudo git commit -m "add app"'
    assert_denied
}

@test "a bypass value inside env -i is still only honoured if it is the real nonce" {
    setup_gate; mkrepo; stage_code
    run gate 'env -i AI_REVIEW_GATE=bogus git commit -m "add app"'
    assert_denied
}

@test "command -v git is not a commit" {
    setup_gate; mkrepo; stage_code
    run gate 'command -v git'
    assert_allowed
}

@test "git -C dir commit is detected" {
    setup_gate; mkrepo; stage_code
    run gate "git -C $REPO commit -m \"add app\""
    assert_denied
}

@test "a commit buried in an && chain is detected" {
    setup_gate; mkrepo; stage_code
    run gate 'npm test && git commit -m "add app" && echo done'
    assert_denied
}

@test "a commit buried in a ; chain is detected" {
    setup_gate; mkrepo; stage_code
    run gate 'echo hi ; git commit -m "add app"'
    assert_denied
}

@test "git commit --amend is detected" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit --amend --no-edit'
    assert_denied
}

@test "git commit-tree is not a commit" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit-tree HEAD^{tree} -m x'
    assert_allowed
}

@test "git log with the word commit in a format string is not a commit" {
    setup_gate; mkrepo; stage_code
    run gate 'git log --format="%H is a commit" -n 5'
    assert_allowed
}

# =========================================================================
# Quote awareness
#
# A naive split on ; && || corrupts on the most ordinary input there is.
# =========================================================================

@test "a message containing separators, -a, and a path parses as one plain commit" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit -m "fix: sanitize input; also update docs && tests -a lib/foo.py"'
    assert_denied
    # If the message had been read as flags, the reason would name a staging flag.
    refute_output --partial 'commits content beyond the index'
}

# =========================================================================
# Heredoc bodies.
#
# The way an agent writes a multi-paragraph commit message, and the way the
# tokenizer used to lose track of where the shell syntax was.
# =========================================================================

@test "an apostrophe in a heredoc commit message does not break the parse" {
    setup_gate; mkrepo; stage_code
    run gate "$(printf '%s\n' \
        "cat > msg.txt <<'EOF'" \
        "fix: explain the gate's message" \
        "EOF" \
        "git commit -F msg.txt")"
    assert_denied
    # The old failure: an unbalanced-quote warning instead of the real reason.
    refute_output --partial 'could not be parsed'
    assert_output --partial 'Staged diff:'
}

@test "a staging flag quoted inside a heredoc body is not read as a flag" {
    setup_gate; mkrepo; stage_code
    run gate "$(printf '%s\n' \
        "cat > msg.txt <<'EOF'" \
        "docs: warn that git commit -a bypasses the index" \
        "EOF" \
        "git commit -F msg.txt")"
    assert_denied
    refute_output --partial 'commits content beyond the index'
}

@test "a real staging flag after a heredoc is still read" {
    setup_gate; mkrepo; stage_code
    run gate "$(printf '%s\n' \
        "cat > msg.txt <<'EOF'" \
        "docs: something" \
        "EOF" \
        "git commit -a -F msg.txt")"
    assert_denied
    assert_output --partial 'commits content beyond the index'
}

@test "a tab-indented <<- delimiter closes its body" {
    setup_gate; mkrepo; stage_code
    run gate "$(printf '%s\n' \
        "cat > msg.txt <<-'EOF'" \
        "	fix: the gate's message" \
        "	EOF" \
        "git commit -a -F msg.txt")"
    assert_denied
    # The body ended, so the -a on the next line was read.
    assert_output --partial 'commits content beyond the index'
}

@test "a herestring is not mistaken for a heredoc" {
    setup_gate; mkrepo; stage_code
    # <<< takes no body. Swallowing the rest as one would hide the commit.
    run gate "$(printf '%s\n' \
        "grep -q x <<< \"nothing to see\"" \
        "git commit -a -m x")"
    assert_denied
    assert_output --partial 'commits content beyond the index'
}

@test "two heredocs opened on one line each get their own body" {
    setup_gate; mkrepo; stage_code
    run gate "$(printf '%s\n' \
        "diff <(cat <<'A') <(cat <<'B')" \
        "git commit -a -m decoy" \
        "A" \
        "git commit -a -m decoy" \
        "B" \
        "git commit -m real")"
    assert_denied
    # Both bodies are data. Only the last line is a commit, and it has no -a.
    refute_output --partial 'commits content beyond the index'
}

@test "an unterminated heredoc still finds the commit that opened it" {
    setup_gate; mkrepo; stage_code
    run gate "$(printf '%s\n' \
        "git commit -a -F - <<'EOF'" \
        "fix: no closing delimiter")"
    assert_denied
    assert_output --partial 'commits content beyond the index'
}

@test "a quoted << that swallows the commit denies rather than losing it" {
    setup_gate; mkrepo; stage_code
    # Not a heredoc at all, but the opener scan cannot see quoting, so it reads
    # `<<file>>` as one and eats every line after it. Silently allowing the
    # commit it ate is the one outcome the gate must not have.
    run gate "$(printf '%s\n' \
        "printf 'usage: cmd <<file>>' > doc.txt" \
        "git commit -m 'add doc'")"
    assert_denied
    assert_output --partial 'could not be parsed'
}

@test "an unparseable command mentioning git and commit denies rather than guesses" {
    setup_gate; mkrepo
    # Unbalanced quote: the git word is swallowed into one opaque token.
    run gate '"git commit -m x'
    assert_denied
    assert_output --partial 'could not be parsed'
}

@test "a command substitution wrapping the git word denies" {
    setup_gate; mkrepo
    # Single quotes on purpose: the gate has to receive the literal $(...) text.
    # shellcheck disable=SC2016
    run gate '$(echo git) commit -m x'
    assert_denied
    assert_output --partial 'could not be parsed'
}

# =========================================================================
# Commands that commit content beyond the index
#
# These are checked before any index-derived rule. Otherwise `git commit -a`
# with a clean index sails through the empty-index check and commits
# unreviewed working-tree changes.
# =========================================================================

@test "-a forces a miss even when the index is empty" {
    setup_gate; mkrepo
    echo changed > "$REPO/base.txt"
    run gate 'git commit -a -m "x"'
    assert_denied
    assert_output --partial 'commits content beyond the index'
}

@test "--all forces a miss even when the index is empty" {
    setup_gate; mkrepo
    run gate 'git commit --all -m "x"'
    assert_denied
}

@test "clustered -am forces a miss" {
    setup_gate; mkrepo
    run gate 'git commit -am "x"'
    assert_denied
    assert_output --partial 'commits content beyond the index'
}

# A CR is not whitespace to the tokenizer, so a staging flag ending a CRLF line
# matched no flag case and the commit read as plain. Real on Windows, where jq
# hands back CRLF.
@test "a staging flag ending a CRLF line is still read" {
    setup_gate; mkrepo
    run gate "$(printf 'git commit -m x --all\r\necho done')"
    assert_denied
    assert_output --partial 'commits content beyond the index'
}

@test "a CRLF line break still separates commands" {
    setup_gate; mkrepo; stage_code
    run gate "$(printf 'echo hi\r\ngit commit -m x')"
    assert_denied
}

@test "--interactive is reported as --interactive, not --patch" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit --interactive -m "x"'
    assert_denied
    assert_output --partial 'beyond the index (--interactive)'
}

@test "--patch is reported as --patch" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit --patch -m "x"'
    assert_denied
    assert_output --partial 'beyond the index (--patch)'
}

@test "--only forces a miss" {
    setup_gate; mkrepo
    run gate 'git commit --only base.txt -m "x"'
    assert_denied
}

@test "--include forces a miss" {
    setup_gate; mkrepo
    run gate 'git commit --include base.txt -m "x"'
    assert_denied
}

@test "-i forces a miss" {
    setup_gate; mkrepo
    run gate 'git commit -i base.txt -m "x"'
    assert_denied
}

@test "a positional pathspec forces a miss" {
    setup_gate; mkrepo
    run gate 'git commit base.txt -m "x"'
    assert_denied
    assert_output --partial 'commits content beyond the index'
}

@test "a pathspec after -- forces a miss" {
    setup_gate; mkrepo
    run gate 'git commit -m "x" -- base.txt'
    assert_denied
}

@test "a redirection is not mistaken for a pathspec" {
    setup_gate; mkrepo
    run gate 'git commit -m "x" > /dev/null'
    # Nothing staged, so this allows; the point is that it is not a pathspec miss.
    assert_allowed
}

# =========================================================================
# Review receipts
# =========================================================================

@test "a clean receipt for this index and HEAD allows" {
    setup_gate; mkrepo; stage_code
    write_receipt clean
    run gate 'git commit -m "add app"'
    assert_allowed
}

@test "a receipt goes stale when the index moves" {
    setup_gate; mkrepo; stage_code
    write_receipt clean
    echo extra > "$REPO/extra.py"
    git -C "$REPO" add extra.py

    run gate 'git commit -m "add app"'
    assert_denied
    assert_output --partial 'the index has changed since'
}

@test "a receipt goes stale when HEAD moves" {
    setup_gate; mkrepo; stage_code
    write_receipt clean
    # Move the base out from under the review without touching the index.
    echo other > "$REPO/other.txt"
    git -C "$REPO" -c core.hooksPath=/dev/null commit -q --only base.txt -m "unrelated" --allow-empty

    run gate 'git commit -m "add app"'
    assert_denied
    assert_output --partial 'HEAD has moved'
}

@test "a needs-review receipt does not satisfy the gate" {
    setup_gate; mkrepo; stage_code
    write_receipt needs-review
    run gate 'git commit -m "add app"'
    assert_denied
    assert_output --partial 'verdict was not clean'
}

@test "a missing receipt misses" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit -m "add app"'
    assert_denied
    assert_output --partial 'no review has been recorded'
}

@test "a corrupt receipts file misses rather than crashing or allowing" {
    setup_gate; mkrepo; stage_code
    mkdir -p "$(state_dir)"
    printf 'not json at all {{{' > "$(state_dir)/receipts.json"

    run gate 'git commit -m "add app"'
    assert_denied
}

@test "receipts are capped at ten, newest first" {
    setup_gate; mkrepo
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        echo "v$i" > "$REPO/app.py"
        git -C "$REPO" add app.py
        write_receipt clean
    done
    run jq 'length' "$(state_dir)/receipts.json"
    assert_output "10"

    run jq -r '.[0].index_tree' "$(state_dir)/receipts.json"
    local newest="$output"
    run git -C "$REPO" write-tree
    assert_output "$newest"
}

# =========================================================================
# Unborn HEAD
#
# `git rev-parse HEAD` exits 128 in a fresh repository, which would break both
# the receipt writer and the gate on the very first commit.
# =========================================================================

@test "the first commit in a fresh repo misses instead of crashing" {
    setup_gate; mkrepo_unborn
    echo "def f(): return 1" > "$REPO/app.py"
    git -C "$REPO" add app.py

    run gate 'git commit -m "initial"'
    assert_denied
}

@test "a receipt written against an unborn HEAD satisfies the gate" {
    setup_gate; mkrepo_unborn
    echo "def f(): return 1" > "$REPO/app.py"
    git -C "$REPO" add app.py
    write_receipt clean

    run jq -r '.[0].head' "$(state_dir)/receipts.json"
    assert_output "unborn"

    run gate 'git commit -m "initial"'
    assert_allowed
}

@test "an empty index in a fresh repo allows" {
    setup_gate; mkrepo_unborn
    run gate 'git commit -m "initial"'
    assert_allowed
}

# =========================================================================
# Tier 1 exemptions
# =========================================================================

@test "nothing staged allows" {
    setup_gate; mkrepo
    run gate 'git commit -m "x"'
    assert_allowed
}

@test "an amend that only rewords allows" {
    setup_gate; mkrepo
    run gate 'git commit --amend -m "better message"'
    assert_allowed
}

@test "a rebase in progress allows" {
    setup_gate; mkrepo
    echo two > "$REPO/base.txt"; git -C "$REPO" commit -qam two
    echo three > "$REPO/base.txt"; git -C "$REPO" commit -qam three

    # Stop the rebase on its first step, so .git/rebase-merge is present.
    cat > "$TEST_TMPDIR/seq-editor" <<'EDITOR'
#!/bin/sh
printf 'break\n' > "$1.tmp"
cat "$1" >> "$1.tmp"
mv "$1.tmp" "$1"
EDITOR
    chmod +x "$TEST_TMPDIR/seq-editor"
    GIT_SEQUENCE_EDITOR="$TEST_TMPDIR/seq-editor" git -C "$REPO" rebase -q -i HEAD~2
    [ -d "$REPO/.git/rebase-merge" ] || [ -d "$REPO/.git/rebase-apply" ]

    stage_code
    run gate 'git commit --amend --no-edit'
    assert_allowed

    git -C "$REPO" rebase --abort
}

@test "an index tree identical to ORIG_HEAD allows" {
    setup_gate; mkrepo
    echo two > "$REPO/base.txt"; git -C "$REPO" commit -qam two
    # A soft reset leaves the index holding the tree ORIG_HEAD points at,
    # which is the invariant a history rewrite preserves by construction.
    git -C "$REPO" reset -q --soft HEAD~1

    run gate 'git commit -m "recommit"'
    assert_allowed
}

@test "a tree that appears only in older reflog entries is not exempt" {
    setup_gate; mkrepo
    echo two > "$REPO/base.txt";   git -C "$REPO" commit -qam two
    echo three > "$REPO/base.txt"; git -C "$REPO" commit -qam three

    # Put the first commit's tree back in the index. It is reachable in the
    # reflog, but not from ORIG_HEAD or HEAD@{1}, so it must still be reviewed.
    git -C "$REPO" read-tree HEAD~2

    run gate 'git commit -m "revive"'
    assert_denied
}

@test "a conflicted index allows, since a merge is already in progress" {
    setup_gate; mkrepo
    git -C "$REPO" checkout -q -b other
    echo theirs > "$REPO/base.txt"; git -C "$REPO" commit -qam theirs
    git -C "$REPO" checkout -q -
    echo ours > "$REPO/base.txt";   git -C "$REPO" commit -qam ours
    git -C "$REPO" merge other >/dev/null 2>&1 || true
    run git -C "$REPO" write-tree
    assert_failure

    run gate 'git commit -m "resolve"'
    assert_allowed
}

# =========================================================================
# Recursion guard
# =========================================================================

@test "a live lock file allows" {
    setup_gate; mkrepo; stage_code
    mkdir -p "$(state_dir)"
    printf '%s\t%s\n' "$$" "$(date +%s)" > "$(state_dir)/running"

    run gate 'git commit -m "add app"'
    assert_allowed
}

@test "a lock file with a dead pid does not allow and is pruned" {
    setup_gate; mkrepo; stage_code
    mkdir -p "$(state_dir)"
    bash -c 'exit 0' & local dead=$!
    wait "$dead" 2>/dev/null || true
    printf '%s\t%s\n' "$dead" "$(date +%s)" > "$(state_dir)/running"

    run gate 'git commit -m "add app"'
    assert_denied
    [ ! -f "$(state_dir)/running" ]
}

@test "a lock file past the age bound does not allow and is pruned" {
    setup_gate; mkrepo; stage_code
    mkdir -p "$(state_dir)"
    # Live pid, but started long enough ago that pid reuse is plausible.
    printf '%s\t%s\n' "$$" "1" > "$(state_dir)/running"

    run gate 'git commit -m "add app"'
    assert_denied
    [ ! -f "$(state_dir)/running" ]
}

@test "AI_REVIEW_GATE=off in the environment allows" {
    setup_gate; mkrepo; stage_code
    export AI_REVIEW_GATE=off
    run gate 'git commit -m "add app"'
    assert_allowed
}

@test "AI_REVIEW_GATE=off inline on the command allows" {
    setup_gate; mkrepo; stage_code
    run gate 'AI_REVIEW_GATE=off git commit -m "add app"'
    assert_allowed
}

# =========================================================================
# PowerShell.
#
# Windows harnesses route some commands through a PowerShell tool rather than
# the Bash one. PowerShell has no `VAR=value command` prefix, so the bypass and
# the nonce arrive as their own statement ahead of the commit, and the gate has
# to both read that form and emit it.
# =========================================================================

@test 'a PowerShell $env: bypass with spaces around = allows' {
    setup_gate; mkrepo; stage_code
    run ps_gate '$env:AI_REVIEW_GATE = "off"; git commit -m "add app"'
    assert_allowed
}

@test 'a PowerShell $env: bypass without spaces around = allows' {
    setup_gate; mkrepo; stage_code
    run ps_gate '$env:AI_REVIEW_GATE="off"; git commit -m "add app"'
    assert_allowed
}

@test 'a PowerShell $env: bypass is matched case-insensitively' {
    setup_gate; mkrepo; stage_code
    run ps_gate "\$Env:ai_review_gate = 'off'; git commit -m 'add app'"
    assert_allowed
}

@test 'a PowerShell $env: assignment after the commit does not bypass' {
    setup_gate; mkrepo; stage_code
    run ps_gate 'git commit -m "add app"; $env:AI_REVIEW_GATE = "off"'
    assert_denied
}

@test 'an unrelated PowerShell $env: assignment does not bypass' {
    setup_gate; mkrepo; stage_code
    run ps_gate '$env:SOMETHING_ELSE = "off"; git commit -m "add app"'
    assert_denied
}

@test "the PowerShell tool gets the bypass in PowerShell syntax" {
    setup_gate; mkrepo; stage_code
    run ps_gate 'git commit -m "add app"'
    assert_denied
    assert_output --partial '$env:AI_REVIEW_GATE = '
    refute_output --partial 'AI_REVIEW_GATE=off git commit'
}

@test "the Bash tool still gets the bypass as a prefix assignment" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit -m "add app"'
    assert_denied
    assert_output --partial 'AI_REVIEW_GATE='
    refute_output --partial '$env:AI_REVIEW_GATE'
}

@test "a nonce issued to the PowerShell tool round-trips in its own syntax" {
    setup_gate; mkrepo; stage_code
    run ps_gate 'git commit -m "add app"'
    assert_denied
    local n
    n=$(ps_nonce_from_output)
    [ -n "$n" ]
    run ps_gate "\$env:AI_REVIEW_GATE = \"$n\"; git commit -m \"add app\""
    assert_allowed
}

@test "a nonce is single-use across shells" {
    setup_gate; mkrepo; stage_code
    run ps_gate 'git commit -m "add app"'
    local n
    n=$(ps_nonce_from_output)
    run ps_gate "\$env:AI_REVIEW_GATE = \"$n\"; git commit -m \"add app\""
    assert_allowed
    run ps_gate "\$env:AI_REVIEW_GATE = \"$n\"; git commit -m \"add app\""
    assert_denied
}

@test "the review loop lock helpers round-trip" {
    setup_gate; mkrepo; stage_code
    (
        cd "$REPO" || exit 1
        source_lib
        review_gate_lock_acquire
    )
    [ -f "$(state_dir)/running" ]
    (
        cd "$REPO" || exit 1
        source_lib
        review_gate_lock_release
    )
    [ ! -f "$(state_dir)/running" ]
}

# =========================================================================
# Modes
# =========================================================================

@test "REVIEW_GATE=off disables the gate entirely" {
    setup_gate; mkrepo; stage_code
    export REVIEW_GATE=off
    run gate 'git commit -m "add app"'
    assert_allowed
}

@test "REVIEW_GATE=off in the config file disables the gate" {
    setup_gate; mkrepo; stage_code
    unset REVIEW_GATE
    printf 'REVIEW_GATE=off\n' > "$HOME/.ai-coding-setup.conf"
    run gate 'git commit -m "add app"'
    assert_allowed
}

@test "the environment beats the config file" {
    setup_gate; mkrepo; stage_code
    printf 'REVIEW_GATE=off\n' > "$HOME/.ai-coding-setup.conf"
    export REVIEW_GATE=block
    run gate 'git commit -m "add app"'
    assert_denied
}

@test "warn is the default mode" {
    setup_gate; mkrepo; stage_code
    unset REVIEW_GATE
    run gate 'git commit -m "add app"'
    assert_warned
}

@test "AI_REVIEW_HEADLESS degrades block to warn" {
    setup_gate; mkrepo; stage_code
    export AI_REVIEW_HEADLESS=1
    run gate 'git commit -m "add app"'
    assert_warned
}

@test "CI degrades block to warn" {
    setup_gate; mkrepo; stage_code
    export CI=true
    run gate 'git commit -m "add app"'
    assert_warned
}

@test "no TTY on any descriptor with no headless marker still blocks" {
    setup_gate; mkrepo; stage_code
    # bats already runs the gate with pipes on every descriptor; a TTY-based
    # headless test would degrade this run to warn-only and quietly turn the
    # gate off everywhere.
    run gate 'git commit -m "add app"'
    assert_denied
}

@test "warn mode does not issue a nonce" {
    setup_gate; mkrepo; stage_code
    export REVIEW_GATE=warn
    run gate 'git commit -m "add app"'
    assert_warned
    [ ! -f "$(state_dir)/nonce" ]
}

@test "warn mode reports the diagnosis and the rubric but not the decision menu" {
    setup_gate; mkrepo; stage_code
    export REVIEW_GATE=warn
    run gate 'git commit -m "add app"'
    assert_warned
    assert_output --partial 'Staged diff:'
    assert_output --partial 'Warn mode, so nothing here stops the commit'
    # Warn cannot stop the commit, but it still has to say which changes want a
    # review first, or "proceeds" is the only instruction the agent reads.
    assert_output --partial 'Classify the change'
    assert_output --partial 'NON-TRIVIAL, review first'
    # Nothing to pick, and no nonce to offer, once the commit already proceeds.
    refute_output --partial 'AskUserQuestion'
    refute_output --partial 'single-use nonce'
}

@test "both modes name the loop script and rule out the review skill" {
    setup_gate; mkrepo; stage_code
    for mode in warn block; do
        export REVIEW_GATE="$mode"
        run gate 'git commit -m "add app"'
        assert_output --partial 'code-review-loop` shell command clears this gate'
        assert_output --partial '`/code-review`'
    done
}

@test "block mode keeps the decision menu" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit -m "add app"'
    assert_denied
    assert_output --partial 'Classify the change'
    assert_output --partial 'AskUserQuestion'
    refute_output --partial 'Warn mode, so nothing here stops the commit'
}

# =========================================================================
# Output shapes
# =========================================================================

@test "claude format nests the decision under hookSpecificOutput" {
    setup_gate; mkrepo; stage_code
    run gate 'git commit -m "add app"'
    assert_success
    run jq -r '.hookSpecificOutput.hookEventName' <<< "$output"
    assert_output "PreToolUse"
}

@test "codex format nests the decision under hookSpecificOutput" {
    setup_gate; mkrepo; stage_code
    export GATE_FORMAT=codex
    run gate 'git commit -m "add app"'
    run jq -r '.hookSpecificOutput.permissionDecision' <<< "$output"
    assert_output "deny"
}

@test "copilot format is flat and carries a reason" {
    setup_gate; mkrepo; stage_code
    export GATE_FORMAT=copilot
    run gate 'git commit -m "add app"'
    assert_success
    local json="$output"
    run jq -r '.permissionDecision' <<< "$json"
    assert_output "deny"
    run jq -r '.permissionDecisionReason | length > 0' <<< "$json"
    assert_output "true"
}

@test "copilot format exits 0 on allow, since a non-zero exit denies there" {
    setup_gate; mkrepo
    export GATE_FORMAT=copilot
    run gate 'git commit -m "x"'
    assert_success
    assert_output ""
}

@test "antigravity format is flat" {
    setup_gate; mkrepo; stage_code
    export GATE_FORMAT=antigravity
    run gate 'git commit -m "add app"'
    run jq -r '.permissionDecision' <<< "$output"
    assert_output "deny"
}

@test "kimi format denies by exit code with the reason on stderr" {
    setup_gate; mkrepo; stage_code
    export GATE_FORMAT=kimi
    run gate 'git commit -m "add app"'
    [ "$status" -eq 2 ]
    assert_output --partial 'Code review gate'
}

# =========================================================================
# Fast path and hygiene
# =========================================================================

@test "a command with no commit substring allows without touching git" {
    setup_gate
    REPO="$TEST_TMPDIR/not-a-repo"
    mkdir -p "$REPO"
    run gate 'ls -la && cat README.md'
    assert_allowed
}

@test "a commit outside a git repository allows" {
    setup_gate
    REPO="$TEST_TMPDIR/not-a-repo"
    mkdir -p "$REPO"
    run gate 'git commit -m "x"'
    assert_allowed
}

@test "--help prints usage" {
    run "$GATE" --help
    assert_success
    assert_output --partial "Usage: review-gate"
}

@test "the deny reason classifies paths by kind" {
    setup_gate; mkrepo
    mkdir -p "$REPO/test" "$REPO/dist"
    echo "def f(): return 1" > "$REPO/app.py"
    echo "def test_f(): pass" > "$REPO/test/test_app.py"
    echo "# notes" > "$REPO/NOTES.md"
    echo "bundled" > "$REPO/dist/bundle.min.js"
    git -C "$REPO" add -A

    run gate 'git commit -m "mixed"'
    assert_denied
    assert_output --partial 'app.py'
    assert_output --partial 'code'
    assert_output --partial 'tests'
    assert_output --partial 'docs'
    assert_output --partial 'generated'
}

@test "a path marked linguist-generated in .gitattributes counts as generated" {
    setup_gate; mkrepo
    printf 'derived/** linguist-generated=true\n' > "$REPO/.gitattributes"
    git -C "$REPO" add .gitattributes
    git -C "$REPO" commit -qm attrs
    mkdir -p "$REPO/derived"
    echo "auto" > "$REPO/derived/out.py"
    git -C "$REPO" add derived/out.py

    run gate 'git commit -m "regen"'
    assert_denied
    assert_output --partial 'derived/out.py'
    assert_output --partial 'generated'
    refute_output --partial 'derived/out.py                                        code'
}

@test "state lands in the right git dir inside a linked worktree" {
    setup_gate; mkrepo
    # `git rev-parse --git-dir` is absolute here, not relative, which is the
    # case a leading-slash prefix test gets wrong on Git for Windows.
    git -C "$REPO" worktree add -q "$TEST_TMPDIR/wt" -b wt
    local main_repo="$REPO"
    REPO="$TEST_TMPDIR/wt"
    echo "def f(): return 1" > "$REPO/app.py"
    git -C "$REPO" add app.py

    run gate 'git commit -m "add app"'
    assert_denied

    local wt_git_dir
    wt_git_dir=$(git -C "$REPO" rev-parse --absolute-git-dir)
    [ -f "$wt_git_dir/ai-review/nonce" ]
    [ ! -e "$main_repo/.git/ai-review/nonce" ]

    write_receipt clean
    run gate 'git commit -m "add app"'
    assert_allowed
}
