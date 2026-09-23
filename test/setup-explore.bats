#!/usr/bin/env bats
# Tests for switching between the two Explore routes in ./setup.
#
# The routes are mutually exclusive, so installing one drops the other. The
# order matters: dropping first and then failing the install leaves the user
# with neither, so the drop must only follow a successful install.
#
# shellcheck disable=SC2030,SC2031

load test_helper

SETUP_SCRIPT="$PROJECT_ROOT/setup"

# Source the definition-only prefix of ./setup (see setup-settings.bats), with
# a stub `claude` that logs every call to $CLAUDE_LOG, reports the plugins in
# $CLAUDE_INSTALLED as installed, and fails `plugin install` when
# $CLAUDE_INSTALL_FAILS is set.
run_switch() { # run_switch <want> <other>
    local defs="$TEST_TMPDIR/setup-defs"
    awk '/^# ---- argument parsing/ { exit } { print }' "$SETUP_SCRIPT" > "$defs"
    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
case "$1 $2" in
    "plugin list")
        for p in $CLAUDE_INSTALLED; do echo "  > $p@ai-coding-setup"; done ;;
    "plugin install")
        [[ -z "${CLAUDE_INSTALL_FAILS:-}" ]] ;;
esac
STUB
    chmod +x "$TEST_TMPDIR/bin/claude"
    export CLAUDE_LOG="$TEST_TMPDIR/claude.log"
    : > "$CLAUDE_LOG"
    run env PATH="$TEST_TMPDIR/bin:$PATH" \
        bash -c "source '$defs'; claude_explore_switch '$1' '$2'"
}

@test "a failed install keeps the route already installed" {
    export CLAUDE_INSTALLED="explore-agent" CLAUDE_INSTALL_FAILS=1
    run_switch explore-model explore-agent
    assert_success
    assert_output --partial "Could not install explore-model"
    run grep -c "plugin uninstall" "$CLAUDE_LOG"
    assert_output 0
}

@test "a successful install drops the other route afterwards" {
    export CLAUDE_INSTALLED="explore-agent"
    run_switch explore-model explore-agent
    assert_success
    run grep -E "plugin (install|uninstall)" "$CLAUDE_LOG"
    assert_line --index 0 --partial "plugin install explore-model@ai-coding-setup"
    assert_line --index 1 "plugin uninstall explore-agent"
}
