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

# ---- statusLine -----------------------------------------------------------

@test "statusline: set when absent and the command mirrors rate_limits" {
    seed_settings '{}'
    run_configure y
    assert_success
    assert_output --partial "mirrors the quota to ~/.claude/rate_limits.json"
    assert_equal "$(jq -r '.statusLine.type' "$HOME/.claude/settings.json")" "command"
    # Feed the command a sample payload and check both the file and the line.
    local cmd; cmd=$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")
    run sh -c "$cmd" <<< '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":12.6},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1},"seven_day":{"used_percentage":41.2,"resets_at":2}}}'
    assert_success
    assert_output "[Opus] ctx 12% · 5h 23% · 7d 41%"
    assert_equal "$(jq -c '.five_hour.used_percentage' "$HOME/.claude/rate_limits.json")" "23.5"
}

@test "statusline: a custom statusLine is never overwritten, hint printed" {
    seed_settings '{"statusLine":{"type":"command","command":"echo mine"}}'
    run_configure y
    assert_success
    assert_output --partial "already have a custom statusLine"
    assert_equal "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" "echo mine"
}

# ---- effort pins ----------------------------------------------------------

@test "effortpins: nothing is written to modelSettings on a fresh config" {
    seed_settings '{}'
    run_configure y
    assert_success
    refute_output --partial "effort pins"
    assert_equal "$(jq -r 'has("modelSettings")' "$HOME/.claude/settings.json")" "false"
}

@test "effortpins: the pins an earlier setup wrote are offered removal" {
    seed_settings '{"modelSettings":{"fable":{"effortLevel":"medium"},"opus":{"effortLevel":"high"}}}'
    run_configure y
    assert_success
    assert_output --partial "effort pins an earlier setup wrote (opus, fable)"
    assert_equal "$(jq -r 'has("modelSettings")' "$HOME/.claude/settings.json")" "false"
}

@test "effortpins: removal keeps a sibling such as maxEffortLevel" {
    seed_settings '{"modelSettings":{"opus":{"effortLevel":"high","maxEffortLevel":"max"}}}'
    run_configure y
    assert_success
    assert_equal "$(jq -c '.modelSettings' "$HOME/.claude/settings.json")" \
        '{"opus":{"maxEffortLevel":"max"}}'
}

@test "effortpins: a level setup never wrote is the user's and is kept" {
    seed_settings '{"modelSettings":{"opus":{"effortLevel":"xhigh"},"fable":{"effortLevel":"medium"}}}'
    run_configure y
    assert_success
    assert_output --partial "wrote (fable)"
    assert_equal "$(jq -c '.modelSettings' "$HOME/.claude/settings.json")" \
        '{"opus":{"effortLevel":"xhigh"}}'
}

@test "effortpins: other models' entries are left alone" {
    seed_settings '{"modelSettings":{"claude-sonnet-5":{"effortLevel":"low"},"claude-opus-5":{"effortLevel":"high"}}}'
    run_configure y
    assert_success
    refute_output --partial "effort pins"
    assert_equal "$(jq -c '.modelSettings' "$HOME/.claude/settings.json")" \
        '{"claude-sonnet-5":{"effortLevel":"low"},"claude-opus-5":{"effortLevel":"high"}}'
}

@test "effortpins: declining keeps the pins" {
    seed_settings '{"modelSettings":{"opus":{"effortLevel":"high"}}}'
    run_configure n
    assert_success
    assert_equal "$(jq -c '.modelSettings' "$HOME/.claude/settings.json")" \
        '{"opus":{"effortLevel":"high"}}'
}

# ---- subagent model -------------------------------------------------------

@test "subagentmodel: written when absent" {
    seed_settings '{"outputStyle":"Concise"}'
    run_configure y
    assert_success
    assert_output --partial "CLAUDE_CODE_SUBAGENT_MODEL=sonnet"
    assert_equal "$(jq -r '.env.CLAUDE_CODE_SUBAGENT_MODEL' "$HOME/.claude/settings.json")" "sonnet"
}

@test "subagentmodel: an existing choice is never overwritten" {
    seed_settings '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"haiku"}}'
    run_configure y
    assert_success
    refute_output --partial "CLAUDE_CODE_SUBAGENT_MODEL=sonnet"
    assert_equal "$(jq -r '.env.CLAUDE_CODE_SUBAGENT_MODEL' "$HOME/.claude/settings.json")" "haiku"
}

# ---- agent teams ----------------------------------------------------------

@test "teams: never added to fresh settings" {
    seed_settings '{"outputStyle":"Concise"}'
    run_configure y
    assert_success
    assert_equal "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$HOME/.claude/settings.json")" "null"
}

@test "teams: the value an earlier setup wrote is removed" {
    seed_settings '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}'
    run_configure y
    assert_success
    assert_output --partial "can't run alongside Code Mode"
    assert_equal "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$HOME/.claude/settings.json")" "null"
    assert_equal "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_CODE_MODE' "$HOME/.claude/settings.json")" "1"
}

# ---- code mode ------------------------------------------------------------

@test "codemode: written when absent, with the notice" {
    seed_settings '{"outputStyle":"Concise"}'
    run_configure y
    assert_success
    assert_output --partial "CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1"
    assert_output --partial "Code Mode is on. It is experimental"
    assert_output --partial "Turn it off"
    assert_equal "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_CODE_MODE' "$HOME/.claude/settings.json")" "1"
}

@test "codemode: an explicit opt-out is never overwritten" {
    seed_settings '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"0"}}'
    run_configure y
    assert_success
    refute_output --partial "CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1"
    refute_output --partial "Code Mode is on"
    assert_equal "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_CODE_MODE' "$HOME/.claude/settings.json")" "0"
}

@test "codemode: declining prints no notice and writes nothing" {
    seed_settings '{"outputStyle":"Concise"}'
    run_configure n
    assert_success
    refute_output --partial "Code Mode is on"
    assert_equal "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_CODE_MODE // "unset"' "$HOME/.claude/settings.json")" "unset"
}

# ---- classic review-gate hook removal -------------------------------------

run_remove_gate() {
    setup_defs
    run bash -c "source '$DEFS'; remove_classic_review_gate_hook"
}

@test "gatehook: only the gate's hook leaves an entry it shares with others" {
    seed_settings '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
        {"type":"command","command":"~/.local/bin/review-gate"},
        {"type":"command","command":"my-own-hook"}]}]}}'
    run_remove_gate
    assert_success
    assert_equal "$(jq -c '[.hooks.PreToolUse[].hooks[].command]' "$HOME/.claude/settings.json")" '["my-own-hook"]'
}

@test "gatehook: an entry left empty is removed, and PreToolUse with it" {
    seed_settings '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
        {"type":"command","command":"~/.local/bin/review-gate"}]}]}}'
    run_remove_gate
    assert_success
    assert_equal "$(jq -c '.hooks | has("PreToolUse")' "$HOME/.claude/settings.json")" "false"
}

@test "gatehook: other entries are left alone" {
    seed_settings '{"hooks":{"PreToolUse":[
        {"matcher":"Bash","hooks":[{"type":"command","command":"~/.local/bin/review-gate"}]},
        {"matcher":"Edit","hooks":[{"type":"command","command":"my-own-hook"}]}]}}'
    run_remove_gate
    assert_success
    assert_equal "$(jq -c '[.hooks.PreToolUse[].matcher]' "$HOME/.claude/settings.json")" '["Edit"]'
}

@test "gatehook: a hook that only mentions review-gate is not the gate" {
    seed_settings '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
        {"type":"command","command":"\"/home/u/.local/bin/review-gate\" --format=claude"},
        {"type":"command","command":"my-review-gate"},
        {"type":"command","command":"echo review-gate"}]}]}}'
    run_remove_gate
    assert_success
    assert_equal "$(jq -c '[.hooks.PreToolUse[].hooks[].command]' "$HOME/.claude/settings.json")" '["my-review-gate","echo review-gate"]'
}

# ---- no prompt-free network access ----------------------------------------

@test "permissions: accepting everything grants no web or remote-git access" {
    run_configure y
    assert_success
    run jq -e '.permissions.allow | index("Bash(cat *)")' "$HOME/.claude/settings.json"
    assert_success
    run jq -e '.permissions.allow | map(select(test("^Web|ls-remote"))) | length == 0' \
        "$HOME/.claude/settings.json"
    assert_success
}

# ---- review-gate mod vs Code Mode -----------------------------------------

# Run install_review_gate_mod with a stub `claude` logging to $CLAUDE_LOG and
# reporting the review-gate mod as installed; every prompt answers yes.
run_gate_mod() {
    setup_defs
    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
[[ "$1 $2" == "plugin list" ]] && echo "  > review-gate@ai-coding-setup"
exit 0
STUB
    chmod +x "$TEST_TMPDIR/bin/claude"
    export CLAUDE_LOG="$TEST_TMPDIR/claude.log"
    : > "$CLAUDE_LOG"
    run env PATH="$TEST_TMPDIR/bin:$PATH" bash -c \
        "source '$DEFS'; prompt_yes_no() { return 0; }; install_review_gate_mod /x/review-gate"
}

@test "gatemod: Code Mode on swaps an installed mod for the PreToolUse hook" {
    seed_settings '{"env":{"CLAUDE_CODE_ENABLE_FUNCTION_HOOKS":"1","CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}}'
    run_gate_mod
    assert_failure
    run cat "$CLAUDE_LOG"
    assert_line "plugin uninstall review-gate"
    refute_line --partial "plugin install"
}

@test "gatemod: Code Mode off still installs the mod" {
    seed_settings '{"env":{"CLAUDE_CODE_ENABLE_FUNCTION_HOOKS":"1","CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"0"}}'
    run_gate_mod
    assert_success
    run cat "$CLAUDE_LOG"
    assert_line --partial "plugin install review-gate@ai-coding-setup"
    refute_line --partial "plugin uninstall"
}
