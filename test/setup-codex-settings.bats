#!/usr/bin/env bats
# Tests for the Codex CLI settings configuration in ./setup.
#
# Same sourcing trick as setup-settings.bats: ./setup has no main guard, so the
# helper extracts the definition-only prefix and calls configure_codex_settings
# directly.
#
# The focus is the [agents] subagent defaults, which have two insertion paths
# (append a new table vs. insert under an existing header) and must leave valid
# TOML either way. A duplicate [agents] header would break the file.
#
# shellcheck disable=SC2030,SC2031

load test_helper

SETUP_SCRIPT="$PROJECT_ROOT/setup"

# ---- fixtures -------------------------------------------------------------

setup_defs() {
    DEFS="$TEST_TMPDIR/setup-defs"
    awk '/^# ---- argument parsing/ { exit } { print }' "$SETUP_SCRIPT" > "$DEFS"
}

# Seed $HOME/.codex/config.toml with the given contents.
seed_config() {
    mkdir -p "$HOME/.codex"
    printf '%s\n' "$1" > "$HOME/.codex/config.toml"
}

# Run configure_codex_settings, answering the single prompt with $1.
run_configure() {
    setup_defs
    run bash -c "source '$DEFS'; configure_codex_settings" <<< "${1:-y}"
}

config() {
    cat "$HOME/.codex/config.toml"
}

# Count of [agents] table headers; more than one is invalid TOML.
agents_headers() {
    grep -c '^\[agents\]' "$HOME/.codex/config.toml"
}

# ---- new table ------------------------------------------------------------

@test "subagent defaults: appends an [agents] table when none exists" {
    seed_config 'model = "gpt-6-astra"'
    run_configure y
    assert_success
    assert_output --partial "run subagents on gpt-6-sol at medium effort"
    assert_equal "$(agents_headers)" "1"
    config | grep -q 'default_subagent_model = "gpt-6-sol"'
    config | grep -q 'default_subagent_reasoning_effort = "medium"'
}

@test "subagent defaults: the original settings survive the append" {
    seed_config 'model = "gpt-6-astra"'
    run_configure y
    assert_success
    config | grep -q '^model = "gpt-6-astra"$'
}

# ---- existing table -------------------------------------------------------

@test "subagent defaults: inserts under an existing [agents] header" {
    seed_config '[agents]
some_other_key = 1'
    run_configure y
    assert_success
    assert_equal "$(agents_headers)" "1"
    config | grep -q 'default_subagent_model = "gpt-6-sol"'
    config | grep -q '^some_other_key = 1$'
}

# ---- gating ---------------------------------------------------------------

@test "subagent defaults: not offered once default_subagent_model is set" {
    seed_config '[features]
multi_agent = true

[agents]
default_subagent_model = "gpt-5.6-luna"'
    run_configure y
    assert_output --partial "nothing to do"
}

@test "subagent defaults: an existing choice is never overwritten" {
    seed_config '[agents]
default_subagent_model = "gpt-5.6-luna"'
    run_configure y
    config | grep -q 'default_subagent_model = "gpt-5.6-luna"'
    refute_line --partial 'default_subagent_model = "gpt-6-sol"'
}

@test "subagent defaults: declining leaves config.toml untouched" {
    seed_config 'model = "gpt-6-astra"'
    run_configure n
    assert_success
    assert_equal "$(config)" 'model = "gpt-6-astra"'
}

# ---- upgrade --------------------------------------------------------------

@test "subagent defaults: a previously pinned default is offered the upgrade" {
    seed_config '[features]
multi_agent = true

[agents]
default_subagent_model = "gpt-5.6-terra"
default_subagent_reasoning_effort = "medium"'
    run_configure y
    assert_success
    assert_output --partial "upgrade gpt-5.6-terra to gpt-6-sol"
    config | grep -q '^default_subagent_model = "gpt-6-sol"$'
    config | grep -q '^default_subagent_reasoning_effort = "medium"$'
    run config
    refute_output --partial 'gpt-5.6-terra'
}

@test "subagent defaults: declining the upgrade keeps the old model" {
    seed_config '[agents]
default_subagent_model = "gpt-5.6-terra"'
    run_configure n
    config | grep -q '^default_subagent_model = "gpt-5.6-terra"$'
}
