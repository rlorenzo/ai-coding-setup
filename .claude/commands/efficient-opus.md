# Efficient Opus

Orchestrate this task with Opus; delegate token-heavy work to cheaper, faster subagents (Sonnet/Haiku via the Task tool). Spend Opus on complexity and judgment; delegate bounded, routine, and high-volume work.

## Your own token discipline

- Search and size-check before reading; read by range or signature, never dump whole files or logs.
- Use Bash (`grep`/`sed`/`awk`/`jq`/`head`) for inspection, large files, and mechanical transforms instead of loading them into context; keep Read+Edit for code changes that need review.
- Batch independent searches in parallel — one message, multiple tool calls.
- Report findings as summaries with `file:line` refs, not raw dumps.

## Keep on Opus

Decomposition, architecture/risk tradeoffs, complex implementation (intricate refactors, multi-file features, subtle bugs), resolving conflicting reports, integrating results, final review and synthesis — and any blocker your next step depends on.

## Delegate

Repo scans, inventory, search; docs/prior-art extraction; browser/test passes, screenshots, log reduction; test-failure clustering; narrow theory-specific debugging; bounded patches and mechanical edits with clear file ownership.

## Model per subagent

- **Haiku** — mechanical, high-volume, low-judgment: search sweeps, inventory, log reduction, simple edits.
- **Sonnet** (default) — low-to-medium complexity: focused research, routine or narrow patches, test runs, straightforward debugging.
- **Opus** — high complexity worth parallelizing or isolating from your context, not for cost savings: intricate refactors, multi-file features, subtle bugs, design exploration, high-stakes reasoning.

Match the tier to task difficulty, not task type — don't push complex implementation down to Sonnet just because it's "implementation."

## Pattern

1. Name the token risk: big search, long logs, broad docs, or repetitive edits.
2. Split independent slices into parallel subagents before reading everything yourself; keep coupled or blocking work local.
3. Give each subagent clear ownership, bounded scope, and verification gates.
4. Require compact returns: findings, `file:line` refs, commands run, diffs, residual risk, stop conditions hit, and what Opus must decide.
5. Decide at the Opus layer: compare, resolve conflicts, choose the path, review the final diff.

## Stay within usage limits

- Delegate in bounded waves — cap parallel subagents (~3 by default), let each wave finish before launching the next, and check usage between waves, not continuously.
- Check real usage with `npx -y ccusage@latest blocks --active --json`; stop launching new work once the 5-hour or weekly window nears ~95% of its cap.
- Don't kill in-flight subagents to claw back marginal budget — let running work finish.

## Pause & resume across windows

For long unattended runs, auto-pause at the cap and resume when it clears:

- When either window hits ~95%, finish the current wave, then schedule a wakeup for `min(3600, secondsUntilWindowClears)` seconds. If the window clears further out than 3600s, chain wakeups — re-schedule on each wake until it clears.
- On resume, re-verify live usage with `ccusage`; don't trust elapsed wall-clock. A fresh `blocks` timestamp (vs. the previous block id) is the real signal the window rolled over.
- Make the wake prompt self-contained: remaining work plan, the 95% rule, the exact usage command, the previous block id, the check-then-reschedule logic, and handoff packets for any subagents that resume.
- Tell the user which window tripped, the observed %, the next check time, and the outstanding work.

## Handoff packets

Write each prompt as if the subagent has no chat context: repo path, exact objective, in/out-of-scope files, return format (files, line refs, commands, diffs, failures, uncertainty), and verification commands plus what success looks like.

## Subagent stop conditions

Stop and report instead of improvising when: live code contradicts the handoff; a verification command fails twice after a fix; the work needs out-of-scope files; or there's no concrete evidence for a claim.

## Vet results

Reports are leads, not facts. Before acting on a high-impact finding, opening a PR, or claiming done: reopen key cited files, confirm line refs and failures, and review the final diff. Resolve subagent disagreements at the Opus layer.

## Guardrails

- Don't delegate a blocker your next step needs.
- Don't let two subagents edit the same files at once.
- Don't trust high-risk conclusions blindly — check the evidence yourself.
- The pattern pays off only when work parallelizes; if a task is tiny or validation needs delicate judgment, keep it on Opus.
