---
name: review-pr
description: "Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review. Use when asked to address, respond to, or clear PR feedback, or to get a PR green and back in front of its reviewers. Operates on an open PR; for local staged work use code-review instead."
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

ALWAYS re-fetch fresh each iteration. Use `gh api graphql --paginate --slurp` with `$endCursor`, then pipe to `jq` (`--slurp` can't be combined with `--jq`):

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
  | jq '[.[].data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)]'
```

**Auto-resolve:** If a thread's first comment body matches any `$IGNORED_FILE` entry (`grep -qxF`), resolve via `resolveReviewThread` mutation without classifying.

If unresolved threads remain → step 3. Do NOT re-request a bot review while threads are still open; process existing feedback first. Only when zero unresolved threads remain → step 5.

### 3. Classify and resolve

Read referenced file + context for each remaining thread, then classify:

- **Already addressed / Informational / Inaccurate**: append body to `$IGNORED_FILE`, resolve (reply with brief explanation if inaccurate).
- **Valid fix**: implement minimal change. Must meet ALL: (1) fixes a real bug (wrong behavior, data loss, security, crash, or race condition); (2) net-simpler or complexity-neutral; (3) concrete, not speculative.
- **Nitpick / Low-value**: resolve WITHOUT implementing. Includes: style preferences not enforced by linter, docstring suggestions on clear code, subjective renames, unnecessary defensive checks, premature abstraction, "consider X instead of Y" where both work, type annotations beyond codebase norms. Append body to `$IGNORED_FILE`, reply with one-line rationale, resolve.

### 4. Push fixes

Stage, commit (`fix:`/`refactor:`/etc.), push, verify CI green, resolve fixed threads. Loop back to step 2.

### 5. Ensure bot review covers latest commit

Each bot's latest review, and the commit it covers:

```bash
head_sha=$(gh pr view {PR_NUMBER} --json commits --jq '.commits[-1].oid')

latest() { gh api --paginate --slurp repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
  | jq -r 'add | [.[] | select(.user.login | endswith("[bot]"))] | group_by(.user.login)
           | map(max_by(.submitted_at)) | .[] | "\(.user.login) \(.commit_id)"'; }
```

`/reviews` alone identifies the review bots; CI and deploy bots never appear there. `--slurp` piped to `jq`, not `--jq`: under `--paginate` a `--jq` filter runs per page, so `max_by` returns a per-page max and lists a long-running PR's bots twice.

All on `head_sha` → success, stop. Otherwise re-trigger each stale bot; they do not re-review a push on their own.

| Bot | Login | Re-trigger with |
| --- | --- | --- |
| Copilot | `copilot-pull-request-reviewer[bot]` | `gh pr edit {PR_NUMBER} --add-reviewer @copilot` |
| CodeRabbit | `coderabbitai[bot]` | `gh pr comment {PR_NUMBER} --body "@coderabbitai review"` |
| Greptile | `greptile-apps[bot]`, `greptileai[bot]` | `gh pr comment {PR_NUMBER} --body "@greptileai review"` |

- Pass the literal `@copilot`; its raw `[bot]` login can exit 0 having requested nothing. Confirm with `gh api repos/{owner}/{repo}/pulls/{PR_NUMBER} --jq '.requested_reviewers[].login'`; empty means it did not take, and the poll below would burn its full timeout waiting.
- App-based bots (CodeRabbit, Greptile) cannot be requested as reviewers at all; a mention is their only trigger. `@coderabbitai full review` re-reviews the whole diff rather than just new commits.
- **Bot not in the table, or none found** → ask the user for the exact trigger. Never guess a mention string: a wrong one posts a visible no-op comment.

Poll until every triggered bot covers `head_sha`, `triggered` holding the logins you re-triggered:

```bash
end=$((SECONDS+900)); sleep 480
while [ $SECONDS -lt $end ]; do
  pending=$(comm -23 <(printf '%s\n' "$triggered" | sort -u) \
                    <(latest | grep " $head_sha$" | cut -d' ' -f1 | sort -u))
  [ -z "$pending" ] && break
  sleep 60
done
```

Run both blocks in one shell: `head_sha` and `latest` do not survive separate tool calls. If your harness blocks foreground `sleep`, run the whole wait as one backgrounded command rather than sleeping between tool calls.

Timeout → name the bots still pending, tell user to re-run this command, stop. Success → go back to step 2.

Stop at iteration 5. Report: threads resolved, fixes made, threads auto-ignored, threads remaining, CI status.
