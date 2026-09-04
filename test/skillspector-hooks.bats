#!/usr/bin/env bats
# The SkillSpector hooks scan .claude/agents one file at a time: the scanner
# takes a single path per run and that directory has no SKILL.md, so it is not
# covered by the recursive skills scan. Without this check a new agent file
# would trigger the hook, get no scan, and pass.

load test_helper

@test "every .claude/agents file is named by a skillspector hook" {
    for agent in "$PROJECT_ROOT"/.claude/agents/*.md; do
        # Without nullglob an unmatched glob loops once on its own literal.
        [[ -e "$agent" ]] || continue
        rel="${agent#"$PROJECT_ROOT/"}"
        # The path, not the path in quotes: YAML lets the scalar be single
        # quoted or bare, and either still names the file to scan.
        grep -qF "$rel" "$PROJECT_ROOT/.pre-commit-config.yaml" ||
            fail "no skillspector hook scans $rel"
    done
}
