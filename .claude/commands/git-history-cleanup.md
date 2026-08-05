---
description: "Rewrite a feature branch's git history into focused, logical commits by folding review-response, fixup, and WIP noise into the changes they belong to. Use when asked to clean up, squash, or tidy a branch's commits before review or merge. Refuses to run on main or other long-lived branches, works on a backup branch, verifies the final tree is identical, then force-pushes with lease and removes the backup."
argument-hint: "[BRANCH]"
---

# Git History Cleanup

Rewrite the commit history of a work branch so each commit is a focused feature, fix, or improvement — not the journey of review responses, lint fixes, and WIP checkpoints it took to get there. The result should read cleanly for reviewers and keep `git blame` pointing at commits that explain *why* a line exists.

## Arguments

- `$ARGUMENTS`: branch to clean (default: the current branch).

## Guards — stop immediately if any fail

1. **Dirty worktree.** `git status --porcelain` must be empty. Otherwise ask the user to commit or stash first.
2. **Target branch.** If a branch is named and differs from the current checkout, verify it exists (`git rev-parse --verify <branch>`) and `git switch <branch>` — every later step operates on the checked-out branch. If the switch fails, stop.
3. **Protected branch.** Resolve the repository's default branch: `git symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/` prefix (e.g. `origin/main` → `main`), falling back to `main`/`master` if the ref is unset. Use that same name everywhere `<default>` appears below. Refuse to run on the default branch, `develop`, `development`, `staging`, `production`, or any `release/*` or `hotfix/*` branch. Only feature/fix/work branches may be rewritten. Explain the refusal and stop.
4. **Nothing to clean.** Compute the base: `base=$(git merge-base origin/<default> HEAD)`. If the branch has zero commits past the base, or its tip is already reachable from the default branch (already merged), say so and stop.
5. **Shared history.** If `git log --format=%ae <base>..HEAD | sort -u` shows author emails other than the current user's (`git config user.email`), or an open PR has other people's commits on it, warn that rewriting will disrupt collaborators and get explicit confirmation before continuing.

## Survey the history

Read the range before touching it:

- `git log --oneline <base>..HEAD` and `git log --stat <base>..HEAD` for the shape.
- Per-commit diffs (`git show`) wherever a message doesn't make the intent obvious.
- Classify each commit: **substantive** (a feature, fix, or refactor that should survive) vs **journey** (fixups, "address review comments", lint/typo/format fixes, WIP checkpoints, revert/re-apply pairs, merge commits pulling in the base branch).

## Plan the new history

Group the branch's net change into logical commits, each one reviewable on its own:

- One commit per feature, fix, or distinct concern. Fold every journey commit into the substantive commit it amends.
- Keep mechanical churn (renames, mass formatting, generated files) separate from behavior changes so blame stays useful.
- Order commits so each builds on the previous — prerequisites and refactors first, then the features that need them.
- Write each commit message in the project's existing style (check `git log -n 20 --oneline` on the default branch); imperative subject, max 72 chars, body only where the subject alone would leave a reviewer guessing.
- Merge commits from the base branch need no special handling: after such a merge, `git merge-base` returns the last base commit merged in, so rewriting onto `<base>` keeps those base changes attributed to the base branch and the merges simply flatten away. Do not rebase onto a newer base tip as part of cleanup — that changes the tree, fails verification, and belongs to a separate "update the branch" task.

Show the user the mapping (old commits → planned commits) before rewriting.

## Execute

1. **Safety net first:** `git branch <branch>-pre-cleanup` on the current tip. It stays until the rewrite is verified and pushed — never delete it before then.
2. Pick the lightest technique that achieves the plan:
   - **Fold and reorder only** (fixups collapse into their parents, order otherwise stands): non-interactive rebase — write the todo list yourself via `GIT_SEQUENCE_EDITOR` (e.g. `GIT_SEQUENCE_EDITOR="cp /path/to/todo" git rebase -i <base>`). Interactive editors are not available; never invoke a rebase that waits on one.
   - **Regrouping across commits** (changes from several commits interleave into new logical units): `git reset --soft <base>`, then rebuild each planned commit by staging the relevant paths/hunks (`git add <paths>`, `git add -p`) and committing in order.
3. If a rebase hits conflicts, resolve them only when the correct resolution is unambiguous — the final tree must equal the original tip. When in doubt, `git rebase --abort` and fall back to the soft-reset rebuild, which cannot conflict.

## Verify

- `git diff <branch>-pre-cleanup HEAD` must be empty. Any difference means the rewrite changed content: report it, `git reset --hard <branch>-pre-cleanup`, and start over or stop.
- Show the new `git log --oneline <base>..HEAD` next to the old one.

## Push and clean up

Only after verification passes:

1. Push the rewritten branch, always naming the destination explicitly so a configured upstream or `pushDefault` cannot redirect it: `git push --force-with-lease origin <branch>` if the branch exists on `origin`, a plain `git push -u origin <branch>` if it doesn't. Never bare `--force` — if the lease is rejected, someone pushed in the meantime; stop and report rather than overwriting their work.
2. Delete the backup branch: `git branch -D <branch>-pre-cleanup`. Delete it only after the push succeeds; if the push failed or was skipped, keep the backup and tell the user it still holds the original history.

## Finish

Report the before/after commit lists, that the branch was force-pushed, and that the backup branch was removed. If an open PR exists, note that its diff is unchanged but review comments anchored to old commits may detach.
