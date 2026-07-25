---
name: efficient-orchestration
description: "Run this task with your current model orchestrating while cheaper subagents do the token-heavy research, coding, and testing. Use for work that is large, parallelizable, or token-hungry — broad repo scans, long logs, wide test or browser passes, repetitive edits — or when the user asks to conserve usage limits. Skip it for small, sequential, or judgment-dense tasks."
---

# Efficient Orchestration

Use your harness's subagent mechanism if it has one (e.g. Claude Code's Task tool, Antigravity subagents); otherwise spawn your own CLI non-interactively per slice with an explicit model (e.g. `codex exec -m <model> "<handoff>"`).

## Tiers

Order the models your harness can run from cheapest to most capable (e.g. on Claude: `Haiku < Sonnet < Opus < Fable`; elsewhere, check a models command or settings panel). You orchestrate from your tier and delegate *down* the ladder; never spend a higher tier than the work justifies.

## Split the work

**Keep on your model:** decomposition, architecture/risk tradeoffs, complex implementation (intricate refactors, multi-file features, subtle bugs), resolving conflicting reports, integration and final review, and any blocker your next step depends on.

**Delegate:** repo scans and search, docs/prior-art extraction, test and browser passes, log reduction, failure clustering, narrow theory-specific debugging, and bounded patches or mechanical edits with clear file ownership.

**Your own token discipline:** search and size-check before reading; read by range, never dump whole files or logs; use `grep`/`sed`/`awk`/`jq`/`head` for inspection and mechanical transforms; batch independent searches in one message; report findings as summaries with `file:line` refs.

## Pick each subagent's model

By task difficulty, not task type — and never above your own tier:

- **Cheapest tier:** mechanical, high-volume, low-judgment work — search sweeps, inventory, log reduction, simple edits.
- **Mid tier (default):** focused research, routine or narrow patches, test runs, straightforward debugging.
- **Your tier:** complex work delegated for parallelism or context isolation, not savings — intricate refactors, multi-file features, subtle bugs, design exploration.

Start at the cheapest tier that can plausibly succeed; after two failures at a tier, escalate one tier or take the work back — never a third retry at the same tier.

Pin an explicit model on every spawn, and where the harness offers stable aliases (e.g. Claude's `haiku`/`sonnet`/`opus`), prefer them over dated full IDs — aliases survive model rotations; pinned IDs hard-fail. Don't assume built-in subagents are cheap: some harnesses default them to inheriting your main-session model (Claude Code's built-in Explore/Plan/general-purpose do; a per-invocation model overrides it, and a user-level `Explore` agent with `model: haiku` catches the spontaneous searches you don't route). Where the harness supports per-agent reasoning effort, run cheap-tier recon and mechanical work at low effort — current-generation low roughly matches previous-generation highest.

## Run it

1. Name the token risk: big search, long logs, broad docs, or repetitive edits.
2. Split independent slices into parallel subagents; keep coupled or blocking work local.
3. Write each handoff as if the subagent has no chat context: repo path, exact objective, in/out-of-scope files, verification commands, success criteria, and the return format (findings, `file:line` refs, commands run, diffs, failures, uncertainty).
4. Tell subagents to stop and report instead of improvising when live code contradicts the handoff, a verification command fails twice after a fix, the work needs out-of-scope files, or a claim lacks concrete evidence.
5. Decide at the orchestration layer: compare, resolve conflicts, choose the path, review the final diff.

## Usage limits

- Know what delegation buys. On pay-per-token APIs, cheaper tiers cut real dollars. On subscriptions, most cost is context reprocessing, and each subagent rebuilds context whose findings flow back into yours — total tokens can rise while the binding quota falls. The durable wins are bucket arbitrage (e.g. Claude's separate Sonnet-only weekly allowance, while the frontier tier drains the shared bucket fastest), wall-clock parallelism, and a lean main context.
- Delegate in bounded waves (~3 parallel); between waves check the harness's usage surface (on Claude Code, `npx -y ccusage@latest blocks --active --json`; elsewhere a usage/status command if one exists, or treat the first rate-limit error as the cap). Stop launching once any usage window nears ~95%; let in-flight work finish.
- For long unattended runs, pause at the cap and resume when it clears: finish the wave, then use the harness's scheduled-wakeup primitive, chaining wakeups of ≤3600s until the window clears — never busy-wait with `sleep`. If no such primitive exists, write a self-contained resume prompt to a handoff file (remaining plan, the 95% rule, the exact usage command and its last reading, subagent handoffs) and tell the user to relaunch with it. On resume, re-verify with the usage command — a fresh block timestamp, not elapsed wall-clock, proves rollover. Tell the user which window tripped, the observed %, the next check time, and the outstanding work.

## Vet results

Reports are leads, not facts. Before acting on a high-impact finding, opening a PR, or claiming done: reopen key cited files, confirm line refs and failures, review the final diff, and resolve subagent disagreements yourself. For non-trivial completed work, spawn a fresh-context verifier on your tier that only tries to refute the claim — rerun the tests, drive the affected flow, probe edge cases — and never fixes anything; independent refutation beats self-review.

## Guardrails

- Don't delegate a blocker your next step needs.
- Don't let two subagents edit the same files, and don't implement slices workers own — coordination plus duplicated implementation costs more than either alone.
- Enforce read-only roles (recon, review, verification) by tool allowlist where the harness supports it, not prompt text.
- Route security-sensitive work (authn/authz, secrets, crypto, hardening) to a capable non-frontier tier — frontier safety classifiers can refuse benign defensive work mid-task.
- If the task is tiny, doesn't parallelize, or needs delicate judgment throughout, skip the ceremony and do it yourself.
