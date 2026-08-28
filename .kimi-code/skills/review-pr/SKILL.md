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

Re-fetch fresh each iteration. `--slurp` can't combine with `--jq`, so pipe to `jq`:

```bash
gh api graphql --paginate --slurp \
  -f query='query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100, after:$endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes { id isResolved comments(first:100){nodes{databaseId body path line author{login}}} }
        }
      }
    }
  }' \
  -f owner="{owner}" -f repo="{repo}" -F pr={PR_NUMBER} \
  | jq '[.[].data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)]'
```

**Auto-resolve:** first comment body matching an `$IGNORED_FILE` entry (`grep -qxF`) → resolve as `WONT_FIX` (see step 3), no classifying.

Threads remain → step 3. Never re-request a bot while threads are open. Zero unresolved → step 5.

### 3. Classify and resolve

Read the referenced file and its context, then classify:

- **Already addressed**: append body to `$IGNORED_FILE`, resolve as `ADDRESSED`.
- **Informational**: append body to `$IGNORED_FILE`, resolve as `WONT_FIX`.
- **Inaccurate**: append body to `$IGNORED_FILE`, reply briefly, resolve as `INVALID`.
- **Valid fix**: implement minimally, then resolve as `ADDRESSED` once step 4 has pushed it. Must meet ALL: (1) real bug: wrong behavior, data loss, security, crash, race; (2) net-simpler or complexity-neutral; (3) concrete, not speculative.
- **Nitpick / Low-value**: resolve WITHOUT implementing: style not enforced by a linter, docstrings on clear code, subjective renames, unnecessary defensive checks, premature abstraction, "consider X instead of Y" where both work, type annotations beyond codebase norms. Append to `$IGNORED_FILE`, reply with a one-line rationale, resolve as `WONT_FIX`.

Resolve with this mutation, substituting the reason the classification names:

```bash
gh api graphql \
  -f query='mutation($id:ID!,$reason:PullRequestReviewThreadResolutionReason) {
    resolveReviewThread(input:{threadId:$id, resolutionReason:$reason}) { thread { isResolved } }
  }' \
  -f id="$THREAD_ID" -f reason=ADDRESSED \
  --jq '.data.resolveReviewThread.thread.isResolved'
```

- `resolutionReason` is Copilot-specific (`PullRequestReviewThreadResolutionReason` is documented as the reason a Copilot review thread was resolved). Send it only when the thread's first comment author is `copilot-pull-request-reviewer`; for every other author drop the `-f reason=...` flag and leave the rest of the command as is. An unsupplied variable is fine, but `-f reason=` with an empty value fails validation.
- The reason is write-only feedback to GitHub. `PullRequestReviewThread` exposes no field that reads it back, so never try to verify what you sent.

### 4. Push fixes

Stage, commit (`fix:`/`refactor:`/etc.), push, verify CI green, resolve fixed threads as `ADDRESSED`. Back to step 2.

### 5. Ensure bot review covers latest commit

```bash
head_sha=$(gh pr view {PR_NUMBER} --json commits --jq '.commits[-1].oid')

latest() { gh api --paginate --slurp repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
  | jq -r 'add | [.[] | select(.user.login | endswith("[bot]"))] | group_by(.user.login)
           | map(max_by(.submitted_at)) | .[] | "\(.user.login) \(.commit_id)"'; }

stale=$(latest | grep -v " $head_sha$" | cut -d' ' -f1 | sort -u)
```

`/reviews` identifies the review bots; CI and deploy bots never appear there. Pipe `--slurp` to `jq`, not `--jq`: under `--paginate` a `--jq` filter runs per page, so `max_by` returns a per-page max and lists a bot twice.

Empty `stale` → success, stop. Otherwise re-trigger each login; bots do not re-review a push on their own.

| Bot | Login | Re-trigger with |
| --- | --- | --- |
| Copilot | `copilot-pull-request-reviewer[bot]` | `gh pr edit {PR_NUMBER} --add-reviewer @copilot` |
| CodeRabbit | `coderabbitai[bot]` | `gh pr comment {PR_NUMBER} --body "@coderabbitai review"` |
| Greptile | `greptile-apps[bot]`, `greptileai[bot]` | `gh pr comment {PR_NUMBER} --body "@greptileai review"` |

- Copilot takes the literal `@copilot` (`--add-reviewer Copilot` fails to resolve). Confirm via raw GraphQL `reviewRequests` only. **Never REST `requested_reviewers` (lists Users only) and never `gh pr view --json reviewRequests` (serializes only Users and Teams): in both, a requested Bot prints as empty and a successful request reads as failed.**

  ```bash
  gh api graphql \
    -f query='query($owner:String!,$repo:String!,$pr:Int!) {
      repository(owner:$owner, name:$repo) {
        pullRequest(number:$pr) {
          reviewRequests(first:20) {
            nodes { requestedReviewer { ... on Bot { login } ... on User { login } } }
          }
        }
      }
    }' \
    -f owner={owner} -f repo={repo} -F pr={PR_NUMBER} \
    --jq '.data.repository.pullRequest.reviewRequests.nodes[].requestedReviewer.login' \
    | grep -q '^copilot-pull-request-reviewer$'
  ```

  `reviewRequests` drops the `[bot]` suffix the table lists. A real miss means the request failed, and the poll below would time out waiting.
- App bots (CodeRabbit, Greptile) can't be requested as reviewers; a mention is the only trigger. `@coderabbitai full review` covers the whole diff, not just new commits.
- **Bot not in the table** → ask the user for the trigger. Never guess a mention string: a wrong one posts a visible no-op comment.

Poll until every triggered bot covers `head_sha`. Set `triggered` to the logins you actually fired, one per line:

```bash
triggered="$stale"   # minus any bot you could not trigger

# Never poll an empty set: comm reports nothing pending, so the loop breaks on
# the first pass and declares success without waiting.
[ -n "$triggered" ] || { echo "nothing was triggered"; exit 1; }

end=$((SECONDS+900)); sleep 480
while [ $SECONDS -lt $end ]; do
  pending=$(comm -23 <(printf '%s\n' "$triggered" | sort -u) \
                    <(latest | grep " $head_sha$" | cut -d' ' -f1 | sort -u))
  [ -z "$pending" ] && break
  sleep 60
done
```

Both blocks in one shell: `head_sha` and `latest` don't survive separate tool calls. If your harness blocks foreground `sleep`, run the whole wait as one backgrounded command.

Timeout → name the bots still pending, tell the user to re-run, stop. Success → back to step 2.

Stop at iteration 5. Report: threads resolved, fixes made, threads auto-ignored, threads remaining, CI status.
