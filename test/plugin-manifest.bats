#!/usr/bin/env bats
# Tests for the Claude Code plugin manifests: the marketplace in
# .claude-plugin/ and the three plugins it lists.
#
# These guard the ways a manifest can drift from the repo without anything
# complaining at install time: a marketplace entry pointing at a plugin that
# is not there, a plugin whose declared name disagrees with the entry, and an
# `agents` key that Claude Code accepts and then ignores.

load test_helper

MARKETPLACE_JSON=".claude-plugin/marketplace.json"

# Every plugin source the marketplace lists, as repo-relative paths.
plugin_sources() {
    # jq on Windows ends lines with CRLF, which would leave a \r on each path.
    jq -r '.plugins[].source' "$PROJECT_ROOT/$MARKETPLACE_JSON" | tr -d '\r'
}

@test "marketplace.json is valid JSON" {
    run jq empty "$PROJECT_ROOT/$MARKETPLACE_JSON"
    assert_success
}

@test "every listed plugin has a manifest at its source" {
    local src
    while IFS= read -r src; do
        [[ -f "$PROJECT_ROOT/$src/.claude-plugin/plugin.json" ]] \
            || fail "no plugin.json under $src"
    done < <(plugin_sources)
}

@test "every plugin manifest is valid JSON" {
    local src
    while IFS= read -r src; do
        run jq empty "$PROJECT_ROOT/$src/.claude-plugin/plugin.json"
        assert_success
    done < <(plugin_sources)
}

@test "each marketplace entry names the plugin its manifest declares" {
    local src listed declared
    while IFS= read -r src; do
        listed=$(jq -r --arg s "$src" '.plugins[] | select(.source == $s) | .name' \
            "$PROJECT_ROOT/$MARKETPLACE_JSON")
        declared=$(jq -r '.name' "$PROJECT_ROOT/$src/.claude-plugin/plugin.json")
        assert_equal "$listed" "$declared"
    done < <(plugin_sources)
}

# The trap this repo walked into once: `claude plugin validate` accepts
# `"agents": ["./path/to/Agent.md"]`, the install succeeds, and the agent is
# silently absent from the loaded plugin. Only the default convention -- an
# `agents/` directory at the plugin root, with no `agents` key at all --
# actually registers one. A directory path in the key fails validation
# outright, so the passing-but-broken file-list form is the only shape worth a
# test, and it is worth testing for every plugin rather than the one that
# ships an agent today.
@test "no plugin declares an agents key, so the agents/ convention applies" {
    local src
    while IFS= read -r src; do
        run jq -e 'has("agents")' "$PROJECT_ROOT/$src/.claude-plugin/plugin.json"
        assert_failure
    done < <(plugin_sources)
}

@test "the explore-agent plugin has an agent for the convention to load" {
    local count
    count=$(find "$PROJECT_ROOT/plugins/explore-agent/agents" \
        -maxdepth 1 -name '*.md' | wc -l)
    [[ "$count" -gt 0 ]]
}

# Every command the root plugin ships comes from the directory the manifest
# names, so a command added outside it would install for the copy path and
# vanish for the plugin path.
@test "plugin commands path points at the canonical command sources" {
    local path
    path=$(jq -r '.commands' "$PROJECT_ROOT/.claude-plugin/plugin.json")
    assert_equal "$path" "./.claude/commands/"
}

# A mod is a plugin whose behaviour is a hooks module, so its manifest carries
# no components of its own; the module is found by the hooks/hooks.json
# convention. An empty modules list would load nothing and say nothing.
@test "every mod names at least one hooks module" {
    local mod hooks count
    for mod in "$PROJECT_ROOT"/mods/*/; do
        [[ -d "$mod" ]] || continue
        hooks="$mod/hooks/hooks.json"
        [[ -f "$hooks" ]] || fail "no hooks/hooks.json in $mod"
        count=$(jq -r '.modules | length' "$hooks")
        [[ "$count" -gt 0 ]] || fail "$hooks names no modules"
    done
}

@test "every mod is listed in the marketplace" {
    local mod name
    for mod in "$PROJECT_ROOT"/mods/*/; do
        [[ -d "$mod" ]] || continue
        name=$(basename "$mod")
        jq -e --arg n "$name" 'any(.plugins[]; .name == $n)' \
            "$PROJECT_ROOT/$MARKETPLACE_JSON" >/dev/null \
            || fail "mod $name is not listed in $MARKETPLACE_JSON"
    done
}

@test "claude plugin validate --strict passes" {
    command -v claude >/dev/null || skip "claude CLI not installed"
    run claude plugin validate "$PROJECT_ROOT" --strict
    assert_success
}

# The mods' own tests run in a child of the claude binary and need neither
# credentials nor a home directory, so they are safe to run from here. CI
# runs them in a dedicated job too; this keeps `test/run` honest locally.
@test "the mods' function-hook tests pass" {
    command -v claude >/dev/null || skip "claude CLI not installed"
    local mod
    for mod in "$PROJECT_ROOT"/mods/*/; do
        [[ -d "$mod" ]] || continue
        CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 run claude plugin test "$mod"
        assert_success
    done
}
