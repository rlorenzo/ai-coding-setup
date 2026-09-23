#!/usr/bin/env bats
# Tests for the Claude Code plugin manifests in .claude-plugin/.
#
# These guard the two ways the manifests can drift from the repo without
# anything complaining at install time: a marketplace entry that names a plugin
# the manifest does not, and an `agents` field that Claude Code accepts and
# then ignores.

load test_helper

PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

@test "plugin.json is valid JSON" {
    run jq empty "$PROJECT_ROOT/$PLUGIN_JSON"
    assert_success
}

@test "marketplace.json is valid JSON" {
    run jq empty "$PROJECT_ROOT/$MARKETPLACE_JSON"
    assert_success
}

@test "marketplace names the plugin the manifest declares" {
    local declared listed
    declared=$(jq -r '.name' "$PROJECT_ROOT/$PLUGIN_JSON")
    listed=$(jq -r '.plugins[] | select(.source == ".") | .name' \
        "$PROJECT_ROOT/$MARKETPLACE_JSON")
    assert_equal "$listed" "$declared"
}

# The trap this repo walked into once: `claude plugin validate` accepts
# `"agents": ["./path/to/Agent.md"]`, the install succeeds, and the agent is
# silently absent from the loaded plugin. Only the default convention -- an
# `agents/` directory at the plugin root, with no `agents` key at all --
# actually registers one. A directory path in the key fails validation outright,
# so the passing-but-broken file-list form is the only shape worth a test.
@test "plugin.json declares no agents key, so the agents/ convention applies" {
    run jq -e 'has("agents")' "$PROJECT_ROOT/$PLUGIN_JSON"
    assert_failure
}

@test "the agents/ directory the convention loads from is non-empty" {
    local count
    count=$(find "$PROJECT_ROOT/agents" -maxdepth 1 -name '*.md' | wc -l)
    [[ "$count" -gt 0 ]]
}

# Every command the plugin ships comes from the directory the manifest names,
# so a command added outside it would install for the copy path and vanish for
# the plugin path.
@test "plugin commands path points at the canonical command sources" {
    local path
    path=$(jq -r '.commands' "$PROJECT_ROOT/$PLUGIN_JSON")
    assert_equal "$path" "./.claude/commands/"
}

@test "claude plugin validate --strict passes" {
    command -v claude >/dev/null || skip "claude CLI not installed"
    run claude plugin validate "$PROJECT_ROOT" --strict
    assert_success
}
