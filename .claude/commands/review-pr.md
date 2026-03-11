# Review PR Feedback Loop

Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review.

## Tooling Constraint

ALL shell operations MUST use `gh api` with `--jq` / `--paginate` and bash only. Never write Python, Node, or any other script file. Never use `curl` for GitHub API calls. Polling loops must be bash `while`/`sleep` inline — no script files.

## Arguments

- `$ARGUMENTS`: The PR number. If omitted, auto-detect via `gh pr view --json number -q .number`.

## Instructions

Extract repo owner/name from `gh repo view --json owner,name`. Before iteration 1, run: `IGNORED_FILE=".review-pr-ignored-${PR_NUMBER}"; touch "$IGNORED_FILE"`. This file persists across all loop iterations. Run this workflow in a loop (max 5 iterations). **Cleanup:** When the workflow ends (success, timeout, or iteration limit), delete `$IGNORED_FILE`.

### 1. Fix failing CI

Run `gh pr checks`. If anything fails, fetch logs with `gh run view <run_id> --log-failed`, fix, commit, push, and wait for green before proceeding.

### 2. Ensure bot review covers latest commit

Get the PR's latest commit SHA via `gh pr view {PR_NUMBER} --json commits --jq '.commits[-1].oid'`. Bots are logins ending in `[bot]`. Get their most recent reviews:

```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
  --jq '[.[] | select(.user.login | endswith("[bot]"))] | group_by(.user.login) | map(max_by(.submitted_at))'
```

If no bot reviews exist or none match the latest SHA, request review:

```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/requested_reviewers \
  -X POST -f "reviewers[]={bot_login}"
```

NOTE: GitHub's REST API fully supports requesting and re-requesting reviews from bot accounts. Do not skip this step or assume it is unsupported.

Poll every 60s using bash (first check at 8 min, timeout 15 min):

```bash
end=$((SECONDS+900)); sleep 480
while [ $SECONDS -lt $end ]; do
  commit_id=$(gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
    --jq '[.[] | select(.user.login=="{bot}")] | max_by(.submitted_at) | .commit_id')
  [ "$commit_id" = "$head_sha" ] && break
  sleep 60
done
```

If no review arrives by timeout, tell the user to retry later and stop.

### 3. Fetch unresolved review threads

ALWAYS re-fetch fresh on every iteration — never reuse data from a prior loop pass.

Use `gh api graphql --paginate --slurp` with `$endCursor` pagination:

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

**Auto-resolve ignored threads:** For each unresolved thread, check if its first comment's body matches any entry in `$IGNORED_FILE` via `grep -qxF "$body" "$IGNORED_FILE"`. If it matches, resolve immediately via `resolveReviewThread` GraphQL mutation without classifying.

**Exit condition:** If zero unresolved threads remain (after auto-resolving ignored ones) and a bot review is confirmed on current HEAD, report success and stop. If ALL threads were auto-resolved from `$IGNORED_FILE`, this also counts as success — the bot is cycling on already-handled issues.

### 4. Classify and resolve comments

For each remaining unresolved thread, read the referenced file and classify:

- **Already addressed / Informational** — append the first comment's body to `$IGNORED_FILE` (`printf '%s\n' "$body" >> "$IGNORED_FILE"`), then resolve the thread silently.
- **Inaccurate** — append the first comment's body to `$IGNORED_FILE`, reply with a brief explanation, then resolve.
- **Valid fix** — implement the minimal code change.
- **Enhancement** — implement if straightforward, otherwise leave open.

Batch-resolve non-actionable threads via `resolveReviewThread` GraphQL mutations.

### 5. Push fixes

Stage changed files, commit with a conventional prefix (`fix:`, `refactor:`, etc.), push, and verify CI is green. Resolve the fixed threads.

### 6. Request bot re-review and wait

Re-request review from the same bot logins identified in step 2:

```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/requested_reviewers \
  -X POST -f "reviewers[]={bot_login}"
```

NOTE: Re-requesting reviews from bot accounts IS supported by the GitHub REST API. Do not skip this step or assume it is unsupported.

Poll every 60s using bash (first check at 8 min, timeout 15 min) until the bot's latest review `commit_id` matches HEAD. Use the same polling snippet from step 2. If timeout, tell the user to re-run `/review-pr` later.

### 7. Loop

After the bot review arrives, go back to **step 3**. Declare success when step 3 finds zero unresolved threads with a confirmed bot review on HEAD, or all remaining threads were auto-resolved from `$IGNORED_FILE`. Stop at iteration 5. Report summary: threads resolved, fixes made, threads auto-ignored, threads remaining, CI status.
