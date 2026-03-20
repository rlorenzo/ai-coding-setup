---
name: commitmsg
description: "Propose a single git commit message for the currently staged changes."
---

# Commit Message

Propose a single git commit message for the currently staged changes.

## Gather context

Run these commands to understand the changes:

- `git diff --staged` — the actual changes
- `git status -s` — staged file list
- `git log -n 20 --oneline` — recent style and to avoid repetition
- `git branch --show-current` — if it contains a ticket ID (e.g. ABC-123), prefix the subject line

## Rules

Use Conventional Commits. Pick the most accurate type; prefer `feat` for new behavior. Optional scope allowed.

Subject: imperative, max 72 chars, no trailing period. Capture the big picture and intent, not implementation details. Optimize for future readers.

Body: include bullets only when the subject alone is insufficient. Each bullet must answer "what would be unclear or risky if omitted?" Merge related items; skip internal plumbing, helpers, and test scaffolding unless they are the primary change. Wrap at 72 chars. Omit the body entirely for minor or single-focus changes.

## Output

```text
[ticket] type(scope): concise subject

- Important change or impact
- Another distinct change, only if necessary
```
