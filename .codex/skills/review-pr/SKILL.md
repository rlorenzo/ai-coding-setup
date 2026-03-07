---
name: review-pr
description: "Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review."
---

# Review PR Feedback Loop

## Arguments

- `$ARGUMENTS`: The PR number. If omitted, auto-detect via `gh pr view --json number -q .number`.

## Instructions

Run this workflow in a loop (max 5 iterations) until no unresolved actionable comments remain.

### Step 1: Check CI status

Run `gh pr checks` on the PR. If any checks are failing, fetch logs with `gh run view <run_id> --log-failed`, fix the issue, commit, push, and wait for CI to pass before proceeding.

### Step 2: Fetch unresolved review comments

Extract repo owner/name from `gh repo view --json owner,name`.

```bash
gh api graphql -f query='
{
  repository(owner: "{owner}", name: "{repo}") {
    pullRequest(number: {PR_NUMBER}) {
      reviewThreads(first: 50) {
        nodes {
          id
          isResolved
          comments(first: 10) {
            nodes {
              databaseId
              body
              path
              line
            }
          }
        }
      }
    }
  }
}'
```

Filter to unresolved threads only. If none, report success and stop.

### Step 3: Classify each comment

Read the referenced file and classify each unresolved comment:

- **Already addressed** — current code handles it. Resolve silently.
- **Inaccurate** — comment misunderstands the code. Reply with brief explanation, then resolve.
- **Informational** — no action needed. Resolve silently.
- **Valid fix** — real issue needing a code change. Implement it.
- **Enhancement** — nice-to-have. Implement if straightforward, otherwise leave open.

### Step 4: Resolve non-actionable threads

Batch-resolve threads using GraphQL:

```bash
gh api graphql -f query='mutation {
  t1: resolveReviewThread(input: {threadId: "THREAD_ID_1"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "THREAD_ID_2"}) { thread { isResolved } }
}'
```

For inaccurate comments, reply first:

```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/comments/{comment_id}/replies \
  -X POST -f body="Not applicable — <brief explanation>."
```

### Step 5: Implement fixes and push

For each valid fix: read the file, implement the minimal change. After all fixes, run the project's linter(s) and fix any violations. Stage specific files, commit with a conventional prefix (`fix:`, `refactor:`, etc.), and push. Verify CI passes after push — if failing, fetch logs, fix, and re-push until green. Then resolve the fixed threads using the same batch mutation from Step 4.

### Step 6: Request bot re-review

Detect bot reviewers (logins ending in `[bot]`):

```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
  --jq '[.[].user.login] | unique | map(select(endswith("[bot]"))) | .[]'
```

For each bot, request re-review:

```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/requested_reviewers \
  -X POST -f "reviewers[]=<bot_login>"
```

If no bot reviewers found, skip to summary.

### Step 7: Wait for bot review

Poll every 60s for up to 15 min (first check after 8 min). Compare the latest bot review `submitted_at` timestamp against when re-review was requested. If no response after 15 min, tell the user to re-run the review-pr skill later.

### Step 8: Loop or finish

If iteration 5 or no new comments, stop. Otherwise loop back to Step 1. Report summary: threads resolved, fixes made, threads remaining, CI status.
