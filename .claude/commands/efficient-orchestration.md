---
description: "Run this task with your current model orchestrating while cheaper subagents do the token-heavy research, coding, and testing."
---

# Efficient Orchestration

Orchestrate this task on your current model; delegate token-heavy work to cheaper, faster subagents. Use your harness's subagent mechanism if it has one (e.g. Claude Code's Task tool, Antigravity subagents); otherwise spawn your own CLI non-interactively per slice with an explicit model (e.g. `codex exec -m <model> "<handoff>"`). Spend your model on complexity and judgment; delegate bounded, routine, and high-volume work.

## Model tiers

Build the ladder from the models your harness can run, ordered cheapest to most capable. On Claude models it is `Haiku < Sonnet < Opus < Fable`; on other harnesses, list what is available (a models command or settings panel) and order it by cost and capability the same way.

You are the orchestrator, running on one of these tiers. Delegate *down* the ladder: when you spawn a subagent, pass the model id for the tier the work needs, and never spend a higher tier than the task justifies. No model names are pinned beyond the example above; everything below is written relative to "your tier."

## Your own token discipline

- Search and size-check before reading; read by range or signature, never dump whole files or logs.
- Use Bash (`grep`/`sed`/`awk`/`jq`/`head`) for inspection, large files, and mechanical transforms instead of loading them into context; keep Read+Edit for code changes that need review.
- Batch independent searches in parallel: one message, multiple tool calls.
- Report findings as summaries with `file:line` refs, not raw dumps.

## Keep on your model

Decomposition, architecture/risk tradeoffs, complex implementation (intricate refactors, multi-file features, subtle bugs), resolving conflicting reports, integrating results, final review and synthesis, and any blocker your next step depends on.

## Delegate

Repo scans, inventory, search; docs/prior-art extraction; browser/test passes, screenshots, log reduction; test-failure clustering; narrow theory-specific debugging; bounded patches and mechanical edits with clear file ownership.

## Model per subagent

Pick the tier by task difficulty, not task type, and don't exceed your own tier for cost savings:

- **Cheapest tier** (bottom of the ladder): mechanical, high-volume, low-judgment work such as search sweeps, inventory, log reduction, simple edits.
- **A mid tier** (a good default): low-to-medium complexity such as focused research, routine or narrow patches, test runs, straightforward debugging.
- **Your own tier** (or an equal-tier isolated subagent), worth parallelizing or isolating from your context rather than for cost savings: intricate refactors, multi-file features, subtle bugs, design exploration, high-stakes reasoning.

Match the tier to task difficulty, not task type: don't push complex implementation down to a mid tier just because it's "implementation."

Pin the tier explicitly on every spawn, and use model aliases (`haiku`, `sonnet`, `opus`) rather than full model IDs — aliases track model rotations and survive access changes; pinned IDs hard-fail when a model is rotated out. Don't assume built-in subagents are cheap: since Claude Code v2.1.198 the built-in Explore, Plan, and general-purpose agents inherit the main-session model (Explore is capped at Opus on the Claude API), so an un-pinned background search bills at your tier. A per-invocation model overrides the agent definition, and a user-level agent file named `Explore` with `model: haiku` shadows the built-in for the spontaneous searches you don't route. If the harness supports per-agent reasoning effort, run cheap-tier recon and mechanical work at low effort — on current-generation models, low effort roughly matches the previous generation's highest setting.

## Pattern

1. Name the token risk: big search, long logs, broad docs, or repetitive edits.
2. Split independent slices into parallel subagents before reading everything yourself; keep coupled or blocking work local.
3. Give each subagent clear ownership, bounded scope, and verification gates.
4. Require compact returns: findings, `file:line` refs, commands run, diffs, residual risk, stop conditions hit, and what you must decide.
5. Decide at the orchestration layer: compare, resolve conflicts, choose the path, review the final diff.

## Stay within usage limits

- Know what delegation buys on your billing model. On pay-per-token APIs, cheaper tiers cut real dollars. On subscriptions, most session cost is context reprocessing (cache reads/writes), and every subagent rebuilds context whose findings then flow back into yours — so total tokens can go *up* even as the quota that binds goes down. The durable subscription wins are bucket arbitrage (e.g. Claude's separate Sonnet-only weekly allowance on top of the shared all-models bucket, which the frontier tier drains fastest), parallel wall-clock, and keeping your own context lean.
- Delegate in bounded waves: cap parallel subagents (~3 by default), let each wave finish before launching the next, and check usage between waves, not continuously.
- Check real usage with your harness's usage surface — on Claude Code, `npx -y ccusage@latest blocks --active --json`; elsewhere, a usage/status command if one exists. If there is none, keep waves small and treat the first rate-limit error as the cap. Stop launching new work once any usage window (e.g. Claude's 5-hour or weekly) nears ~95% of its cap.
- Don't kill in-flight subagents to claw back marginal budget; let running work finish.

## Pause & resume across windows

For long unattended runs, auto-pause at the cap and resume when it clears:

- When a usage window hits ~95%, finish the current wave, then pause. If your harness has a scheduled-wakeup or timer primitive, schedule a wakeup for `min(3600, secondsUntilWindowClears)` seconds; if the window clears further out than 3600s, chain wakeups by re-scheduling on each wake until it clears. If no such primitive exists, do NOT busy-wait with `sleep` loops — instead write the wake prompt below to a handoff file (e.g. `orchestration-resume.md`), tell the user when the window clears and to relaunch with that file, and stop.
- On resume, re-verify live usage with the same usage command; don't trust elapsed wall-clock. On Claude Code, a fresh `ccusage blocks` timestamp (vs. the previous block id) is the real signal the window rolled over.
- Make the wake prompt self-contained: remaining work plan, the 95% rule, the exact usage command and its last reading, the check-then-reschedule logic, and handoff packets for any subagents that resume.
- Tell the user which window tripped, the observed %, the next check time, and the outstanding work.

## Handoff packets

Write each prompt as if the subagent has no chat context: repo path, exact objective, in/out-of-scope files, return format (files, line refs, commands, diffs, failures, uncertainty), and verification commands plus what success looks like.

## Subagent stop conditions

Stop and report instead of improvising when: live code contradicts the handoff; a verification command fails twice after a fix; the work needs out-of-scope files; or there's no concrete evidence for a claim.

## Vet results

Reports are leads, not facts. Before acting on a high-impact finding, opening a PR, or claiming done: reopen key cited files, confirm line refs and failures, and review the final diff. Resolve subagent disagreements at the orchestration layer.

For non-trivial completed work, prefer independent refutation over self-review: spawn a fresh-context verifier on your own tier whose only job is to refute the claim — rerun the tests, drive the affected flow, probe edge cases — and that never fixes anything itself. Fresh-context verifiers catch what the implementer (including you) is primed to miss.

## Guardrails

- Don't delegate a blocker your next step needs.
- Don't let two subagents edit the same files at once.
- Don't keep implementing slices yourself while workers own them; paying for coordination *and* duplicated implementation costs more than either alone.
- Route security-sensitive work (authn/authz, secrets, crypto, hardening) to a capable non-frontier tier: frontier-model safety classifiers can refuse benign defensive-security work mid-task.
- Don't trust high-risk conclusions blindly; check the evidence yourself.
- The pattern pays off only when work parallelizes; if a task is tiny or validation needs delicate judgment, keep it on your own model.
