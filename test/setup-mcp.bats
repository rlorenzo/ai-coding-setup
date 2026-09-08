#!/usr/bin/env bats
# Tests for the MCP auto-approve permission path in ./setup.
#
# `setup` is a single top-level script with no main guard, so sourcing it whole
# would run the installer. Everything above the argument-parsing marker is
# constants and function definitions, so the helper below sources just that
# prefix and calls the MCP functions directly.
#
# The focus is the per-tool grant syntax. Claude's own "mcp__<server>__*" is
# meaningless to Antigravity, which parses only "mcp(<server>/*)" and silently
# drops anything else from settings.json on its next launch. A regression here
# is invisible except as a permission prompt that returns every session, so
# these tests pin the translation, the detection of the translated value, and
# the idempotence of a second pass over an already-granted config.
#
# shellcheck disable=SC2030,SC2031

load test_helper

SETUP_SCRIPT="$PROJECT_ROOT/setup"

ANTIGRAVITY_DIR=".gemini/antigravity-cli"

# ---- fixtures -------------------------------------------------------------

# Extract the definition-only prefix of ./setup into a sourceable file.
setup_defs() {
    DEFS="$TEST_TMPDIR/setup-defs"
    awk '/^# ---- argument parsing/ { exit } { print }' "$SETUP_SCRIPT" > "$DEFS"
}

# Run a snippet with the ./setup definitions in scope.
with_defs() {
    setup_defs
    run bash -c "source '$DEFS'; $1"
}

# Seed Antigravity's settings.json with the given JSON.
seed_antigravity_settings() {
    mkdir -p "$HOME/$ANTIGRAVITY_DIR"
    echo "$1" > "$HOME/$ANTIGRAVITY_DIR/settings.json"
}

# Seed Antigravity's mcp_config.json with the playwright server configured.
seed_antigravity_mcp() {
    mkdir -p "$HOME/$ANTIGRAVITY_DIR"
    echo '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest"]}}}' \
        > "$HOME/$ANTIGRAVITY_DIR/mcp_config.json"
}

# Put no-op `antigravity` and `npx` stubs on PATH so configure_mcp proceeds.
stub_tools() {
    mkdir -p "$TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TEST_TMPDIR/bin/antigravity"
    printf '#!/bin/sh\nexit 0\n' > "$TEST_TMPDIR/bin/npx"
    chmod +x "$TEST_TMPDIR/bin/antigravity" "$TEST_TMPDIR/bin/npx"
    export PATH="$TEST_TMPDIR/bin:$PATH"
}

# Run configure_mcp for Antigravity, answering every prompt with $1.
run_configure_antigravity() {
    setup_defs
    local answer="${1:-y}"
    run bash -c "source '$DEFS'; configure_mcp antigravity Antigravity antigravity" <<< "$answer
$answer"
}

# The permissions.allow array Antigravity ended up with.
antigravity_allow() {
    jq -c '.permissions.allow' "$HOME/$ANTIGRAVITY_DIR/settings.json"
}

# ---- translation ----------------------------------------------------------

@test "mcp_permission_for: Antigravity gets its own mcp(server/*) syntax" {
    with_defs 'mcp_permission_for antigravity playwright "mcp__playwright__*"'
    assert_success
    assert_output 'mcp(playwright/*)'
}

@test "mcp_permission_for: Claude keeps the pattern it was given" {
    with_defs 'mcp_permission_for claude playwright "mcp__playwright__*"'
    assert_success
    assert_output 'mcp__playwright__*'
}

@test "mcp_permission_for: an unknown tool keeps the pattern it was given" {
    with_defs 'mcp_permission_for copilot playwright "mcp__playwright__*"'
    assert_success
    assert_output 'mcp__playwright__*'
}

@test "mcp_permission_for: the server name is interpolated, not hardcoded" {
    with_defs 'mcp_permission_for antigravity boostgraph "mcp__boostgraph__*"'
    assert_success
    assert_output 'mcp(boostgraph/*)'
}

# ---- detection ------------------------------------------------------------

@test "is_mcp_permitted: the translated grant is found in Antigravity settings" {
    seed_antigravity_settings '{"permissions":{"allow":["mcp(playwright/*)"]}}'
    with_defs 'is_mcp_permitted antigravity "mcp(playwright/*)"'
    assert_success
}

@test "is_mcp_permitted: a Claude-style grant does not count for Antigravity" {
    seed_antigravity_settings '{"permissions":{"allow":["mcp__playwright__*"]}}'
    with_defs 'is_mcp_permitted antigravity "mcp(playwright/*)"'
    assert_failure
}

@test "is_mcp_permitted: an absent settings.json is not permitted" {
    with_defs 'is_mcp_permitted antigravity "mcp(playwright/*)"'
    assert_failure
}

# ---- what configure_mcp writes --------------------------------------------

@test "configure_mcp: Antigravity is offered and written the translated grant" {
    stub_tools
    seed_antigravity_mcp
    run_configure_antigravity y
    assert_success
    assert_output --partial 'mcp(playwright/*)'
    refute_output --partial 'mcp__playwright__*'
    assert_equal "$(antigravity_allow)" '["mcp(playwright/*)"]'
}

@test "configure_mcp: an existing settings.json keeps its other keys" {
    stub_tools
    seed_antigravity_mcp
    seed_antigravity_settings '{"theme":"dark"}'
    run_configure_antigravity y
    assert_success
    assert_equal "$(jq -r '.theme' "$HOME/$ANTIGRAVITY_DIR/settings.json")" 'dark'
    assert_equal "$(antigravity_allow)" '["mcp(playwright/*)"]'
}

@test "configure_mcp: declining leaves Antigravity settings untouched" {
    stub_tools
    seed_antigravity_mcp
    seed_antigravity_settings '{"theme":"dark"}'
    run_configure_antigravity n
    assert_success
    assert_output --partial 'mcp(playwright/*)'
    assert_equal "$(jq -c . "$HOME/$ANTIGRAVITY_DIR/settings.json")" '{"theme":"dark"}'
}

# ---- idempotence ----------------------------------------------------------

@test "configure_mcp: a granted Antigravity config is not offered again" {
    stub_tools
    seed_antigravity_mcp
    seed_antigravity_settings '{"permissions":{"allow":["mcp(playwright/*)"]}}'
    run_configure_antigravity y
    assert_success
    refute_output --partial 'Auto-approve permissions to add'
    assert_equal "$(antigravity_allow)" '["mcp(playwright/*)"]'
}

@test "configure_mcp: two runs leave a single grant, not a duplicate" {
    stub_tools
    seed_antigravity_mcp
    run_configure_antigravity y
    assert_success
    run_configure_antigravity y
    assert_success
    assert_equal "$(antigravity_allow)" '["mcp(playwright/*)"]'
}

# ---- the file stays usable ------------------------------------------------

@test "configure_mcp: the written Antigravity settings.json is valid JSON" {
    stub_tools
    seed_antigravity_mcp
    run_configure_antigravity y
    assert_success
    run jq empty "$HOME/$ANTIGRAVITY_DIR/settings.json"
    assert_success
}
