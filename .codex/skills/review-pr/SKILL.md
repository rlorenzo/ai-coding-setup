---
name: review-pr
description: "Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review."
---

# Review PR Feedback Loop

## Arguments

- `$ARGUMENTS`: The PR number. If omitted, auto-detect via `gh pr view --json number -q .number`.

## Instructions

Extract repo owner/name from `gh repo view --json owner,name`. Run this workflow in a loop (max 5 iterations).

### 1. Fix failing CI

Run `gh pr checks`. If anything fails, fetch logs with `gh run view <run_id> --log-failed`, fix, commit, push, and wait for green before proceeding.

### 2. Ensure bot review covers latest commit

Get the PR's latest commit SHA and each bot reviewer's most recent `commit_id`. Bots are logins ending in `[bot]`.

If no bot reviews exist or none match the latest SHA, request review via `gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/requested_reviewers -X POST -f "reviewers[]=<bot>"` and poll every 60s (first check at 8 min, timeout 15 min). Stop and tell the user to retry later if no review arrives.

### 3. Fetch unresolved review threads

Use the `reviewThreads` GraphQL query (fields: `id`, `isResolved`, `comments.nodes.{databaseId, body, path, line, author.login}`). Filter to unresolved threads only.

**Exit condition:** If zero unresolved threads and a bot review is confirmed on current HEAD, report success and stop.

### 4. Classify and resolve comments

For each unresolved comment, read the referenced file and classify it:

- **Already addressed / Informational** — resolve the thread silently.
- **Inaccurate** — reply with a brief explanation, then resolve.
- **Valid fix** — implement the minimal code change.
- **Enhancement** — implement if straightforward, otherwise leave open.

Batch-resolve non-actionable threads via `resolveReviewThread` GraphQL mutations.

### 5. Push fixes

Stage changed files, commit with a conventional prefix (`fix:`, `refactor:`, etc.), push, and verify CI is green. Resolve the fixed threads.

### 6. Request bot re-review and wait

Request re-review from the same bots found in step 2. Poll every 60s (first check at 8 min, timeout 15 min) until a new review's `commit_id` matches HEAD. If timeout, tell user to re-run the review-pr skill later.

### 7. Loop

After the bot review arrives, go back to **step 3**. Only declare success when step 3 finds zero unresolved threads with a confirmed bot review on HEAD. Stop at iteration 5. Report summary: threads resolved, fixes made, threads remaining, CI status.
