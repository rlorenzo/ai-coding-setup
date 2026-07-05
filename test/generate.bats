#!/usr/bin/env bats
# Tests for tools/generate — the derived-file generator that keeps the
# per-tool skills and shared prompts in sync with .claude/commands/.

load test_helper

# Copy the source tree pieces the generator needs into an isolated tmp repo.
copy_repo() {
    cp -r "$PROJECT_ROOT/.claude" "$PROJECT_ROOT/.codex" "$PROJECT_ROOT/.copilot" \
        "$PROJECT_ROOT/.antigravity" "$PROJECT_ROOT/prompts" "$TEST_TMPDIR/"
    mkdir -p "$TEST_TMPDIR/tools"
    cp "$PROJECT_ROOT/tools/generate" "$TEST_TMPDIR/tools/"
}

@test "committed skills and prompts are in sync with .claude/commands sources" {
    run "$PROJECT_ROOT/tools/generate" --check
    assert_success
    assert_output --partial "in sync"
}

@test "generate --check fails when a derived skill drifts" {
    copy_repo
    echo "drift" >> "$TEST_TMPDIR/.codex/skills/commitmsg/SKILL.md"
    run "$TEST_TMPDIR/tools/generate" --check
    assert_failure
    assert_output --partial "stale: .codex/skills/commitmsg/SKILL.md"
}

@test "generate --check fails when a derived prompt drifts" {
    copy_repo
    echo "drift" >> "$TEST_TMPDIR/prompts/code-review.md"
    run "$TEST_TMPDIR/tools/generate" --check
    assert_failure
    assert_output --partial "stale: prompts/code-review.md"
}

@test "generate rewrites a stale derived file" {
    copy_repo
    echo "drift" >> "$TEST_TMPDIR/.copilot/skills/code-review/SKILL.md"
    run "$TEST_TMPDIR/tools/generate"
    assert_success
    run "$TEST_TMPDIR/tools/generate" --check
    assert_success
}

@test "generate fails when a source command lacks a description" {
    copy_repo
    local src="$TEST_TMPDIR/.claude/commands/commitmsg.md"
    awk '!/^description:/' "$src" > "$src.tmp" && mv "$src.tmp" "$src"
    run "$TEST_TMPDIR/tools/generate" --check
    assert_failure
    assert_output --partial "no 'description'"
}

@test "generated skill frontmatter carries name and source description" {
    run head -3 "$PROJECT_ROOT/.codex/skills/commitmsg/SKILL.md"
    assert_success
    assert_output --partial "name: commitmsg"
    assert_output --partial "description:"
}
