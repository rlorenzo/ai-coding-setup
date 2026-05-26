---
name: review-pr
description: "Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review."
---

# Review PR Feedback Loop

## Constraints

ALL shell operations: `gh api` with `--jq`/`--paginate` and bash only. No Python/Node/script files. No `curl` for GitHub API. Polling loops must be inline bash `while`/`sleep`.

## Arguments

- `$ARGUMENTS`: PR number (default: auto-detect via `gh pr view --json number -q .number`).

## Setup

Extract owner/name from `gh repo view --json owner,name`. Set `IGNORED_FILE=".review-pr-ignored-${PR_NUMBER}"` and `touch` it. Run the workflow loop (max 5 iterations). Delete `$IGNORED_FILE` on exit.

## Workflow

### 1. Fix failing CI

Run `gh pr checks`. On failure: `gh run view <run_id> --log-failed`, fix, commit, push, wait for green.

### 2. Fetch unresolved threads

ALWAYS re-fetch fresh each iteration. Use `gh api graphql --paginate --slurp` with `$endCursor`:

```bash
gh api graphql --paginate --slurp \
  -f query='query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String) {
    repository(owner:$owner,name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100,after:$endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes { id isResolved comments(first:100){nodes{databaseId body path line author{login}}} }
        }
      }
    }
  }' \
  -f owner="{owner}" -f repo="{repo}" -F pr={PR_NUMBER} \
  --jq '[.[].data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)]'
```

**Auto-resolve:** If a thread's first comment body matches any `$IGNORED_FILE` entry (`grep -qxF`), resolve via `resolveReviewThread` mutation without classifying.

If unresolved threads remain → step 3. Do NOT re-request a bot review while threads are still open — process existing feedback first. Only when zero unresolved threads remain → step 5.

### 3. Classify and resolve

Read referenced file + context for each remaining thread, then classify:

- **Already addressed / Informational / Inaccurate** — append body to `$IGNORED_FILE`, resolve (reply with brief explanation if inaccurate).
- **Valid fix** — implement minimal change. Must meet ALL: (1) fixes a real bug — wrong behavior, data loss, security, crash, or race condition; (2) net-simpler or complexity-neutral; (3) concrete, not speculative.
- **Nitpick / Low-value** — resolve WITHOUT implementing. Includes: style preferences not enforced by linter, docstring suggestions on clear code, subjective renames, unnecessary defensive checks, premature abstraction, "consider X instead of Y" where both work, type annotations beyond codebase norms. Append body to `$IGNORED_FILE`, reply with one-line rationale, resolve.

### 4. Push fixes

Stage, commit (`fix:`/`refactor:`/etc.), push, verify CI green, resolve fixed threads. Loop back to step 2.

### 5. Ensure bot review covers latest commit

Only reached when zero unresolved threads remain. Get HEAD SHA: `gh pr view {PR_NUMBER} --json commits --jq '.commits[-1].oid'`. Bots = logins ending in `[bot]`. Fetch their latest reviews:

```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
  --jq '[.[] | select(.user.login | endswith("[bot]"))] | group_by(.user.login) | map(max_by(.submitted_at))'
```

If a bot's latest review already covers HEAD → success. Stop.

Otherwise, re-request and poll (first check 8 min, timeout 15 min, poll 60 s). `gh pr edit --add-reviewer` re-requests reviews from existing bot reviewers — do not skip this.

```bash
bot_logins=$(gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
  --jq '[.[] | select(.user.login | endswith("[bot]")) | .user.login] | unique | .[]')

for bot in $bot_logins; do
  gh pr edit {PR_NUMBER} --add-reviewer "$bot"
done

end=$((SECONDS+900)); sleep 480
while [ $SECONDS -lt $end ]; do
  commit_id=$(gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
    --jq '[.[] | select(.user.login=="{bot}")] | max_by(.submitted_at) | .commit_id')
  [ "$commit_id" = "$head_sha" ] && break
  sleep 60
done
```

Timeout → tell user to re-run the review-pr skill and stop. Success → go back to step 2.

Declare success when step 2 finds zero unresolved threads AND step 5 confirms a bot review on HEAD. Stop at iteration 5. Report: threads resolved, fixes made, threads auto-ignored, threads remaining, CI status.
