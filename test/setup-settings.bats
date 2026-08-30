#!/usr/bin/env bats
# Tests for the Claude Code settings configuration in ./setup.
#
# `setup` is a single top-level script with no main guard, so sourcing it whole
# would run the installer. Everything above the argument-parsing marker is
# constants and function definitions, so the helper below sources just that
# prefix and calls configure_claude_settings directly.
#
# The focus is the attribution gate: which existing configs get offered the
# change, which are left alone, and what lands in the file. A user who has
# deliberately chosen their own attribution must never be overwritten.
#
# shellcheck disable=SC2030,SC2031

load test_helper

SETUP_SCRIPT="$PROJECT_ROOT/setup"

# ---- fixtures -------------------------------------------------------------

# Extract the definition-only prefix of ./setup into a sourceable file.
setup_defs() {
    DEFS="$TEST_TMPDIR/setup-defs"
    awk '/^# ---- argument parsing/ { exit } { print }' "$SETUP_SCRIPT" > "$DEFS"
}

# Seed $HOME/.claude/settings.json with the given JSON.
seed_settings() {
    mkdir -p "$HOME/.claude"
    echo "$1" > "$HOME/.claude/settings.json"
}

# Run configure_claude_settings, answering every prompt with $1 (default "y").
# Both prompts (feature settings, read-only permissions) read one line each.
run_configure() {
    setup_defs
    local answer="${1:-y}"
    run bash -c "source '$DEFS'; configure_claude_settings" <<< "$answer
$answer"
}

# The attribution value the run produced.
attribution() {
    jq -c '.attribution' "$HOME/.claude/settings.json"
}

# ---- offered when unset ---------------------------------------------------

@test "attribution: offered and written when settings.json does not exist" {
    run_configure y
    assert_success
    assert_output --partial "disable commit/PR/session attribution tags"
    assert_equal "$(attribution)" '{"commit":"","pr":"","sessionUrl":false}'
}

@test "attribution: offered and written when the key is absent" {
    seed_settings '{"outputStyle":"Concise"}'
    run_configure y
    assert_success
    assert_output --partial "disable commit/PR/session attribution tags"
    assert_equal "$(attribution)" '{"commit":"","pr":"","sessionUrl":false}'
}

# ---- migration of pre-sessionUrl configs ----------------------------------

@test "attribution: adds sessionUrl to a config written before it existed" {
    seed_settings '{"attribution":{"commit":"","pr":""}}'
    run_configure y
    assert_success
    assert_output --partial "disable commit/PR/session attribution tags"
    assert_equal "$(attribution)" '{"commit":"","pr":"","sessionUrl":false}'
}

# ---- left alone once set or chosen ----------------------------------------

@test "attribution: not offered once all three keys are set" {
    seed_settings '{"attribution":{"commit":"","pr":"","sessionUrl":false}}'
    run_configure y
    assert_success
    refute_output --partial "disable commit/PR/session attribution tags"
    assert_equal "$(attribution)" '{"commit":"","pr":"","sessionUrl":false}'
}

@test "attribution: an explicit sessionUrl=true is never overwritten" {
    seed_settings '{"attribution":{"commit":"","pr":"","sessionUrl":true}}'
    run_configure y
    assert_success
    refute_output --partial "disable commit/PR/session attribution tags"
    assert_equal "$(attribution)" '{"commit":"","pr":"","sessionUrl":true}'
}

@test "attribution: a custom commit trailer is never overwritten" {
    seed_settings '{"attribution":{"commit":"Made by Claude"}}'
    run_configure y
    assert_success
    refute_output --partial "disable commit/PR/session attribution tags"
    assert_equal "$(attribution)" '{"commit":"Made by Claude"}'
}

# ---- declining --------------------------------------------------------------

@test "attribution: declining the prompt leaves settings.json untouched" {
    seed_settings '{"outputStyle":"Concise"}'
    run_configure n
    assert_success
    assert_output --partial "disable commit/PR/session attribution tags"
    assert_equal "$(jq -c . "$HOME/.claude/settings.json")" '{"outputStyle":"Concise"}'
}

# ---- the file stays usable --------------------------------------------------

@test "attribution: the written settings.json is valid JSON" {
    seed_settings '{"env":{"EXISTING":"1"}}'
    run_configure y
    assert_success
    run jq empty "$HOME/.claude/settings.json"
    assert_success
    assert_equal "$(jq -r '.env.EXISTING' "$HOME/.claude/settings.json")" "1"
}
