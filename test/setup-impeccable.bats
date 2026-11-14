#!/usr/bin/env bats
# Tests for the Impeccable step in ./setup: Claude Code gets the plugin, the
# other agents get the npx installer, and Claude is never in the npx list
# (both at once installs every skill twice).
#
# shellcheck disable=SC2030,SC2031

load test_helper

SETUP_SCRIPT="$PROJECT_ROOT/setup"

# Source the definition-only prefix of ./setup with stub `claude` and `npx`
# that log every call to $STUB_LOG. `claude plugin list` reports the plugins in
# $CLAUDE_INSTALLED; the prompt is answered yes.
run_impeccable() { # run_impeccable <tool>...
    local defs="$TEST_TMPDIR/setup-defs"
    awk '/^# ---- argument parsing/ { exit } { print }' "$SETUP_SCRIPT" > "$defs"
    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "$STUB_LOG"
case "$1 $2" in
    "plugin list")
        for p in ${CLAUDE_INSTALLED:-}; do echo "  ❯ $p@impeccable"; done ;;
esac
STUB
    printf '#!/usr/bin/env bash\necho "npx $*" >> "$STUB_LOG"\n' > "$TEST_TMPDIR/bin/npx"
    chmod +x "$TEST_TMPDIR/bin/claude" "$TEST_TMPDIR/bin/npx"
    export STUB_LOG="$TEST_TMPDIR/stub.log"
    : > "$STUB_LOG"
    run env PATH="$TEST_TMPDIR/bin:$PATH" bash -c \
        "source '$defs'; prompt_yes_no() { return 0; }; selected_tools=($*); configure_impeccable_skills"
}

@test "Claude gets the plugin and is left out of the npx providers" {
    run_impeccable claude codex copilot
    assert_success
    run cat "$STUB_LOG"
    assert_line "claude plugin install impeccable@impeccable --scope user --yes"
    assert_line --partial "install --providers=codex,github --scope=global"
    refute_line --partial "providers=claude"
}

@test "an installed plugin is updated, not reinstalled" {
    export CLAUDE_INSTALLED="impeccable"
    run_impeccable claude
    assert_success
    run cat "$STUB_LOG"
    assert_line "claude plugin update impeccable@impeccable"
    refute_line --partial "plugin install"
    refute_line --partial "npx"
}

@test "without Claude selected, only npx runs" {
    run_impeccable codex
    assert_success
    run cat "$STUB_LOG"
    refute_line --partial "claude plugin"
    assert_line --partial "install --providers=codex --scope=global"
}
