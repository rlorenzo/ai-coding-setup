# ai-coding-setup

Set of prompts, skills, and scripts to aid in utilizing AI coding agents in development workflows.

## Prerequisites

The `setup` script and the review loops are Bash scripts that shell out to a handful of command-line tools. Install the ones below and make sure they are on your `PATH`.

**Required** (the `setup` script exits early if any is missing):

- [`git`](https://git-scm.com/), to clone the repo and drive the `git`-based commands
- [GitHub CLI (`gh`)](https://cli.github.com/) 2.88.0+, installed and authenticated (`/review-pr` uses the `gh pr edit --add-reviewer @copilot` special value added in 2.88.0 to re-request Copilot code review)
- [`jq`](https://jqlang.github.io/jq/), a JSON processor used to read and edit each tool's settings and MCP config files

**Required only for optional steps:**

- [Node.js (`npx`)](https://nodejs.org/), for the MCP servers and the Impeccable design skills. `setup` skips those steps with a warning if `npx` is not found.

**At least one AI coding tool:**

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Codex CLI](https://github.com/openai/codex)
- [Copilot CLI](https://docs.github.com/en/copilot/copilot-cli)
- Antigravity CLI (using the `agy` command)
- [Kimi Code CLI](https://www.kimi.com/code) (using the `kimi` command)

### Installing the prerequisites

| Tool | macOS (Homebrew) | Debian / Ubuntu | Windows (winget) |
| --- | --- | --- | --- |
| `git` | `brew install git` | `sudo apt install git` | bundled with [Git for Windows](https://git-scm.com/downloads/win) |
| `gh` | `brew install gh` | [gh install docs](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) | `winget install GitHub.cli` |
| `jq` | `brew install jq` | `sudo apt install jq` | `winget install jqlang.jq` |
| Node.js | `brew install node` | `sudo apt install nodejs npm` | `winget install OpenJS.NodeJS` |

The other utilities the scripts call (`bash`, `grep`, `sed`, `awk`, `sort`, `diff`, `find`, `comm`, ...) are standard on macOS and Linux, and are bundled with Git for Windows.

> **Windows:** Run `./setup` and the review loops from [Git Bash](https://git-scm.com/downloads/win) (part of Git for Windows). Git Bash ships Bash and the standard Unix utilities but **not `jq`**, so install `jq` separately with the command above.

## Quick Start

```bash
git clone https://github.com/rlorenzo/ai-coding-setup.git
cd ai-coding-setup
./setup
```

The script detects which AI tools you have installed and walks you through installing commands for each one interactively.

> **Windows:** Run the setup script from [Git Bash](https://git-scm.com/downloads/win).

## Supported Tools

| Tool | Command format | Source directory | Installs to |
| --- | --- | --- | --- |
| Claude Code | Markdown (`.md`) | `.claude/commands/` | `~/.claude/commands/` |
| Claude Code agents | Markdown (`.md`) | `.claude/agents/` | `~/.claude/agents/` |
| Codex CLI | Agent Skills (`SKILL.md`) | `.codex/skills/` | `~/.codex/skills/` |
| Copilot CLI | Agent Skills (`SKILL.md`) | `.copilot/skills/` | `~/.copilot/skills/` |
| Antigravity CLI | Unified Plugin (`plugin.json`) | `.antigravity/` | `~/.gemini/antigravity-cli/plugins/ai-coding-setup/` |
| Kimi Code CLI | Agent Skills (`SKILL.md`) | `.kimi-code/skills/` | `~/.kimi-code/skills/` |
| Shared prompts | Markdown (`.md`) | `prompts/` | `~/.local/share/ai-coding-setup/prompts/` |

Kimi Code reads its user-level data from `$KIMI_CODE_HOME` when that variable is set; `setup` honors it and falls back to `~/.kimi-code`. Kimi invokes skills as `/skill:<name>`, so the commands below are `/skill:commitmsg`, `/skill:review-pr`, and so on.

## Available Commands

### /commitmsg

Propose a conventional commit message for the currently staged changes. Detects ticket IDs from branch names and follows the project's recent commit style.

**Usage:**

- Claude Code: `/commitmsg`
- Codex CLI: `$commitmsg`
- Copilot CLI: `/commitmsg`
- Antigravity CLI: `/commitmsg`
- Kimi Code CLI: `/skill:commitmsg`

### /review-pr

Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review.

**Usage:**

- Claude Code: `/review-pr [PR_NUMBER]`
- Codex CLI: `$review-pr [PR_NUMBER]`
- Copilot CLI: `/review-pr [PR_NUMBER]`
- Antigravity CLI: `/review-pr [PR_NUMBER]`
- Kimi Code CLI: `/skill:review-pr [PR_NUMBER]`

### /code-refinement

Review staged files for code quality (KISS, DRY, YAGNI, Clean Code), fix linting issues, and check test coverage.

**Usage:**

- Claude Code: `/code-refinement`
- Codex CLI: `$code-refinement`
- Copilot CLI: `/code-refinement`
- Antigravity CLI: `/code-refinement`
- Kimi Code CLI: `/skill:code-refinement`

### /code-review

Run a standalone code review on staged changes. Writes findings to `agent-code-review.md`.

**Usage:**

- Claude Code: `/code-review`
- Codex CLI: `$code-review`
- Copilot CLI: `/code-review`
- Antigravity CLI: `/code-review`
- Kimi Code CLI: `/skill:code-review`

### /dependency-review

Audit dependency updates for supply-chain risk before they land: publish-age gate, changelog/diff verification, security advisories, community signals, and breaking changes.

**Usage:**

- Claude Code: `/dependency-review`
- Codex CLI: `$dependency-review`
- Copilot CLI: `/dependency-review`
- Antigravity CLI: `/dependency-review`
- Kimi Code CLI: `/skill:dependency-review`

### /efficient-orchestration

Run a task with your current model as the orchestrator and reviewer while cheaper, faster subagents do the token-heavy research, coding, and testing. It matches model tier to task difficulty (your own tier for complex work, a mid tier for low/medium, the cheapest tier for mechanical), keeps the orchestrator's own reading and searching lean, runs delegation in bounded waves to respect your usage caps, and for long unattended runs auto-pauses and resumes across usage windows. No model names are hardcoded beyond a Claude example ladder: each harness orders its own available models by cost and capability, and everything else is written relative to whatever tier you are on. Agents without a native subagent tool (Codex, Copilot) delegate by spawning their own CLI non-interactively with an explicit model.

The skill also pins the model explicitly on every spawn (since Claude Code v2.1.198 the built-in Explore/Plan/general-purpose subagents inherit the main-session model, so an un-pinned background search bills at your tier), prefers model aliases over pinned IDs, drops reasoning effort for cheap-tier recon, distinguishes what delegation buys on API vs. subscription billing (per-token savings vs. quota-bucket arbitrage), and closes non-trivial work with a fresh-context verifier that only refutes, never fixes.

**Usage:**

- Claude Code: `/efficient-orchestration`
- Codex CLI: `$efficient-orchestration`
- Copilot CLI: `/efficient-orchestration`
- Antigravity CLI: `/efficient-orchestration`
- Kimi Code CLI: `/skill:efficient-orchestration`

### /git-history-cleanup

Rewrite a feature branch's git history into focused, logical commits before review or merge. It surveys the branch's commits past the merge base, folds review-response, fixup, WIP, and lint-fix noise into the substantive commits they amend, and reorders the result so each commit is reviewable on its own and `git blame` stays meaningful. Refuses to run on `main` or other long-lived branches, creates a backup branch before rewriting, and verifies the final tree is byte-identical to the original tip. Once verified it force-pushes with `--force-with-lease` (never bare `--force`) and deletes the backup branch; on any failure the backup is kept so the original history is never lost.

**Usage:**

- Claude Code: `/git-history-cleanup [BRANCH]`
- Codex CLI: `$git-history-cleanup [BRANCH]`
- Copilot CLI: `/git-history-cleanup [BRANCH]`
- Antigravity CLI: `/git-history-cleanup [BRANCH]`
- Kimi Code CLI: `/skill:git-history-cleanup [BRANCH]`

## Claude Code Agents

Beyond commands, `setup` installs user-level subagent definitions from [.claude/agents/](.claude/agents/) to `~/.claude/agents/`. These are Claude Code-only (the other harnesses have no equivalent mechanism).

### Explore

Since Claude Code v2.1.198 the built-in `Explore` subagent [inherits your main-session model](https://code.claude.com/docs/en/sub-agents) instead of always running on Haiku (capped at Opus on the Claude API). If your daily driver is Opus or Fable, every background codebase search Claude spontaneously delegates bills at that tier. This agent shadows the built-in (a user-level agent with the same name overrides it, which the docs explicitly support) and pins exploration back to `haiku` at `effort: low` with read-only tools.

Trade-off to know about: a custom `Explore` loads your `CLAUDE.md`/user memory like any subagent, which the built-in skips for speed. To remove it, delete `~/.claude/agents/Explore.md`.

## Review Loops

Two multi-agent feedback loops live in [bin/](bin/): `code-review-loop` (for staged code) and `plan-review-loop` (for plan documents), alongside `review-gate`, the hook that keeps an agent from committing before the first of those has run. Each loop pairs an **editor** agent with a different **reviewer** agent and iterates until the reviewer is satisfied or `--max-iterations` is hit. Using two different models for editing and reviewing surfaces issues a single agent tends to miss in its own output.

Both scripts are installed onto your `PATH` by `./setup` and rely on the prompts in [prompts/](prompts/) (installed to `~/.local/share/ai-coding-setup/prompts/`).

### code-review-loop

Runs a full review cycle over your **staged changes**:

1. **Refinement**: editor agent runs the `code-refinement` prompt (lint, KISS/DRY/YAGNI, test coverage). Skip with `-s`.
2. **Stage**: any fixes from refinement are staged.
3. **Initial review**: reviewer agent writes findings to `agent-code-review.md`.
4. **Fix → re-review loop**: editor responds to findings, reviewer re-reviews, repeat until clean or max iterations.
5. **Summary**: editor writes a narrative summary to `agent-review-summary.md`.

A pre-review snapshot of your staged work is saved to the git stash so you can restore the original if the loop mangles something. Partially staged files are rejected up front, so fully stage or unstage before running.

**Usage:**

```bash
code-review-loop                                # default agents, 5 iterations
code-review-loop -m 3                           # cap at 3 review cycles
code-review-loop -s                             # skip the refinement step
code-review-loop --editor claude --reviewer codex
```

**Outputs (project root):** `agent-code-review.md` (latest findings), `agent-review-summary.md` (narrative).

**When a run fails, read the logs.** Each agent's full output is written to a per-run directory, printed in the banner at startup and again whenever an agent exits non-zero:

```text
 Logs           : ~/.cache/code-review-loop/20260807-142516
```

One file per step, named for the step and the agent that ran it:

```text
1-refinement.claude.log
3-review-initial.antigravity.log
4.1-response.claude.log
6.1-review.antigravity.log
final-summary.claude.log
```

Each records the agent, the tools it was allowed, its combined stdout and stderr, and its exit code. This is the difference between "it failed" and knowing why: a loop that stops with a bare `Execution error` on the terminal leaves nothing else behind, and a run started in the background does not even have the scrollback. Note that an agent failing does not stop the loop; it logs the failure and carries on, so the log is often the only sign a step went wrong.

Logs are kept for **one day** and older runs are pruned at startup. Retention is by age rather than by count because the loop tends to be run several times in a sitting, and what you come back for is today's failure. Override with `REVIEW_LOOP_LOG_DAYS`, or set `CODE_REVIEW_LOOP_LOG_DIR` to keep logs somewhere of your own, which opts out of pruning entirely.

### plan-review-loop

Iteratively improves a **plan document** through review feedback:

1. **Initial review**: reviewer agent reads the plan, writes structured feedback to `feedback-plan.md`.
2. **Improve → re-review loop**: editor revises the plan in place, reviewer re-reviews, repeat until the reviewer emits `NO_FURTHER_FEEDBACK` or max iterations.
3. **Summary**: editor writes a narrative summary to `plan-review-summary.md`.

**Usage:**

```bash
plan-review-loop PLAN-feature.md
plan-review-loop -m 3 PLAN-feature.md
plan-review-loop --reviewer claude --editor codex PLAN-feature.md
```

**Outputs (project root):** the plan file is edited in place; `feedback-plan.md` (latest feedback, removed when reviewer is satisfied); `plan-review-summary.md` (narrative).

### review-gate

A hook that stops a coding agent from committing code nobody reviewed.

Every harness has a pre-tool event that can deny a tool call. `review-gate` sits on that event, watches for a `git commit`, and answers one question in well under a second: does this staged change already have a clean review? If it does, or if the commit is not really a code change at all, the agent never sees the gate. If it does not, the gate denies the commit and hands the agent the staged diff, per-category line counts, and a rubric, and the agent either judges the change trivial and says so out loud, or asks you what to do.

Only `code-review-loop` clears the gate: it is the one thing that writes the review receipt. The `/code-review` slash command this repo also installs reviews the same staged diff and writes `agent-code-review.md`, but records nothing the gate can read, so the deny message names the script and rules the skill out by name.

The gate never runs `code-review-loop` itself. That takes minutes and is designed to hand back to a human at the end; the gate is pure git plumbing, and the loop runs afterward as an ordinary foreground command if you pick that option.

**What passes without a word:**

- nothing staged, or an `--amend` that only rewords
- a clean review receipt for exactly this index on exactly this base, which is what `code-review-loop` records when it finishes
- a history rewrite: rebase, interactive rebase, cherry-pick, revert, or merge, including every `--continue` step. A twelve-commit rebase must not stop to ask twelve times
- an index tree identical to `ORIG_HEAD` or `HEAD@{1}`, which catches a rewrite whose in-progress markers are already cleaned up
- an unresolved merge conflict in the index, which means a merge is in progress anyway
- `AI_REVIEW_GATE=off` on the command, or `REVIEW_GATE=off` in the config

**What always gets stopped:** `git commit -a`, `git commit <path>`, and the `-o` / `--only` / `-i` / `--include` forms. They commit content that was not in the index when the gate ran, so a matching receipt describes something else. That check runs before every index-derived rule, or `git commit -a` with a clean index would sail through the empty-index check and land unreviewed work.

**Modes**, set with `REVIEW_GATE` in `~/.ai-coding-setup.conf` or in the environment (the environment wins):

| Mode | Behavior |
| --- | --- |
| `warn` | Default. Prints the reason and the trivial/non-trivial rubric, asks the agent to run `code-review-loop` on a non-trivial change or to say out loud that it skipped it, and lets the commit through either way. Nothing enforces it. |
| `block` | Denies the commit and hands the agent the reason. |
| `off` | Disabled. |

It ships in `warn` because the rubric is untested against your commits and a wrong `block` is far more annoying than a wrong `warn`. Once a few weeks of warn output shows it is not crying wolf, switch to `block`.

**Escape hatches**, in the order you are likely to want them:

- `AI_REVIEW_GATE=off git commit -m "..."` bypasses one commit. In PowerShell, where that prefix form is a parse error, write it as `$env:AI_REVIEW_GATE = "off"; git commit -m "..."`. The gate reads the bypass off the command string rather than its own environment, so it has to sit on the same command as the commit either way.
- The gate issues a single-use nonce with every block, scoped to the index as it stands. The agent uses it to act on its own trivial-change judgment: `AI_REVIEW_GATE=<nonce> git commit -m "..."`. Staging more work invalidates it, and it works once.
- `REVIEW_GATE=off` in `~/.ai-coding-setup.conf` turns the gate off everywhere.

**Headless runs degrade to warn.** In CI, or under `AI_REVIEW_HEADLESS=1`, there is nobody to ask, and a gate that hard-blocks there deadlocks the build. Detection is explicit and never a TTY check: every harness spawns hooks with pipes on all three descriptors, so keying off `[ -t 0 ]` would degrade every interactive run too, and quietly turn the gate off everywhere while still looking installed.

**Installation.** `./setup` offers to wire it into Claude Code and defaults to yes, appending a `PreToolUse` hook to `~/.claude/settings.json` without disturbing hooks that are already there. Accepting it is safe: the gate ships in `warn` mode, so it logs an unreviewed commit and lets it through until you set `REVIEW_GATE=block`. Answer `n` at the prompt to skip it. The script speaks every harness's output shape via `--format`, but only Claude is wired automatically, because the other four take different config shapes and paths that are worth confirming against their current docs before writing into your config:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [
          { "type": "command", "command": "\"$HOME/.local/bin/review-gate\" --format=claude" }
        ]
      }
    ]
  }
}
```

Available formats: `claude` and `codex` emit the decision nested under `hookSpecificOutput`; `copilot` and `antigravity` emit a flat `{"permissionDecision": ..., "permissionDecisionReason": ...}`; `kimi` is exit-code driven, blocking with exit 2 and the reason on stderr. The allow path is always silence and exit 0, never an affirmative `"allow"`: an affirmative allow from a `PreToolUse` hook would skip your own permission rules and auto-approve every shell command the agent runs.

**Windows.** The gate is a Bash script, so it needs Git Bash, like the rest of this repo. Everything it calls is bundled with Git for Windows except `jq`, which you install separately; without `jq` the gate allows every commit rather than failing, so check that it is on `PATH` before trusting the gate there. Claude Code runs hook commands through Git Bash on Windows by default, falling back to PowerShell only when Git Bash is absent, so the Git Bash style path `./setup` writes into `~/.claude/settings.json` (`/c/Users/you/.local/bin/review-gate`) resolves as written.

Three Windows specifics are worth knowing:

- **The matcher has to name both shell tools.** Windows exposes a `PowerShell` tool alongside `Bash`, and a matcher of `Bash` alone lets every commit made through the other one straight past the gate. `./setup` writes `Bash|PowerShell`, and widens an existing `Bash`-only entry in place when you re-run it.
- **The bypass takes PowerShell syntax there.** A bash `AI_REVIEW_GATE=off git commit ...` prefix is a parse error in PowerShell, so the gate reads the statement form too, and writes whichever one matches the tool the commit is coming from into its own deny message: `$env:AI_REVIEW_GATE = "off"; git commit ...`. Either way it has to ride on the same command as the commit. The gate is a separate process spawned before your command runs, so it never inherits a variable you set in an earlier call; it can only read what is on the command string in front of it.
- **It costs about 150ms per shell call.** The hook fires on every command the agent runs, not just commits, and process startup under Git Bash is far slower than on macOS or Linux. The non-commit fast path exits before any git call or subshell, but bash itself still has to start. Measured here: roughly 160ms warm against 55ms for a bare `bash -c true`, and over a second on a cold file cache.

`./setup` falls back to copying when `ln -s` cannot make a real symlink, which is the default on Windows unless Developer Mode is on. That works, but `~/.local/bin/review-gate` is then a snapshot rather than a link, so re-run `./setup` to pick up changes to the script.

**Known blind spot:** a commit made inside a script the agent invokes is invisible, because the gate only ever sees the command the agent typed. Nothing short of a git-level hook closes that, and a git-level hook cannot ask a question, so it would only ever warn after the fact.

**State** lives in `$(git rev-parse --git-dir)/ai-review/`, so it is never committed, is per-worktree, and survives branch switches:

| File | Contents |
| --- | --- |
| `receipts.json` | The last 10 review results, newest first: index tree, HEAD, verdict, cycles, agents, timestamp. |
| `nonce` | The outstanding single-use bypass and the index tree it was issued for. |
| `running` | The active `code-review-loop`'s PID and start time. The gate exempts commits while the loop runs, and prunes the file when the PID is dead or the timestamp is too old to trust. |

### Configuration

Defaults are `--editor claude --reviewer codex`. Override per-run with `-e` / `-r`, or persist defaults in `~/.ai-coding-setup.conf`:

```ini
EDITOR_AGENT=claude
REVIEWER_AGENT=codex
REVIEW_GATE=warn
```

Supported agents: `claude`, `codex`, `copilot`, `antigravity`, `kimi`. Only the agents you actually have installed need to be referenced.

Two caveats for `kimi`: it takes its prompt as a command-line argument (there is no stdin form), so on Windows/Git Bash a very large prompt can exceed the OS argument limit. Copilot has the same limitation. And it has no per-run flag to disable MCP servers, so an autonomous loop run still loads whatever is configured in `~/.kimi-code/mcp.json`.

Both loops write their working files (`agent-code-review.md`, `agent-review-summary.md`, `feedback-plan.md`, `plan-review-summary.md`) to the target project's root. Consider adding those names to that project's `.gitignore` (or your global gitignore) so an agent never commits them by accident.

Environment variables:

| Variable | Default | Effect |
| --- | --- | --- |
| `CODE_REVIEW_LOOP_LOG_DIR` | `~/.cache/code-review-loop/<timestamp>` | Where `code-review-loop` writes its run logs. Setting it also turns off log pruning, on the grounds that a directory you named is yours to manage. |
| `REVIEW_LOOP_LOG_DAYS` | `1` | Delete run logs older than this many days. Only applies to the default location. |
| `AI_CODING_SETUP_PROMPTS_DIR` | `~/.local/share/ai-coding-setup/prompts` | Where the loops read their prompts from. |
| `REVIEW_GATE` | `warn` | `review-gate` mode: `off`, `warn`, or `block`. Overrides the config file. |
| `AI_REVIEW_GATE` | unset | `off` bypasses the gate for one invocation. Also carries the single-use nonce the gate issues. Read off the command string, as a `VAR=value` prefix or a PowerShell `$env:AI_REVIEW_GATE = "..."` statement, so it must sit on the same command as the commit. |
| `AI_REVIEW_HEADLESS` | unset | `1` degrades the gate to warn-only. `code-review-loop` sets it for its own run. |
| `REVIEW_GATE_LOCK_MAX_AGE` | `21600` | Seconds before the gate stops trusting a `code-review-loop` lock file and prunes it. |

### Shared prompts

Both loops are driven by agent-agnostic prompts in [prompts/](prompts/), not interactive commands. They're listed here so you can audit or tweak the behavior:

| Prompt | Used by | Role |
| --- | --- | --- |
| `code-refinement.md` | code-review-loop | Editor's lint/refine pre-review step |
| `code-review.md` | code-review-loop | Reviewer's initial pass |
| `code-review-followup.md` | code-review-loop | Reviewer's follow-up passes |
| `code-review-response.md` | code-review-loop | Editor's response to findings |
| `plan-review.md` | plan-review-loop | Reviewer's initial pass |
| `plan-review-followup.md` | plan-review-loop | Reviewer's follow-up passes |

## How It Works

- Each AI tool has its own command format, but the content is maintained once: `.claude/commands/*.md` files are the canonical sources, and `tools/generate` derives the Codex/Copilot/Antigravity/Kimi `SKILL.md` files and the shared loop prompts from them. A pre-commit/CI check (`tools/generate --check`) fails if the derived files drift from their sources.
- The `setup` script copies selected commands to the appropriate user-level directory for each tool.
- Shared prompts are installed to `~/.local/share/ai-coding-setup/prompts/` and referenced by the review loop scripts.
- Installed commands are tagged with a source marker so the script can safely update them later without overwriting your custom commands that happen to share the same name.
- On each run the script also offers to prune stale installs: any command it previously installed (identified by that same marker) that no longer exists in the repo can be removed, so renamed or deleted commands clean themselves up. It asks before each removal (default No, so nothing is dropped without your say-so), or pass `--force` to prune without prompting. Your own unmarked commands are never touched.

## MCP Server Configuration

The setup script can configure [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) servers for your AI tools. Currently supported:

| Server | Package | Description |
| --- | --- | --- |
| [Playwright](https://github.com/microsoft/playwright-mcp) | `@playwright/mcp@latest` | Browser automation and web testing |

MCP servers are added via each tool's `mcp add` CLI command at user scope. Tools without one (Copilot, Antigravity, Kimi Code) get their JSON config file edited directly; for Kimi that is `~/.kimi-code/mcp.json`, whose only built-in editor is the interactive `/mcp-config` TUI command.

## `gh` Agent Skills

Beyond the commands in this repo, `setup` can install GitHub's **upstream** agent skills for each selected tool. These come from the GitHub CLI team and are unrelated to the commands/skills this repo ships:

| Skill | Repo | What it teaches |
| --- | --- | --- |
| `gh` | [`cli/cli`](https://github.com/cli/cli#agent-skills) | Driving `gh` well: structured JSON output, pagination, repo targeting, search vs. list, `gh api` fallback |
| `gh-stack` | [`github/gh-stack`](https://github.com/github/gh-stack) | [Stacked pull requests](#stacked-pull-requests): creating a stack, adding layers, `submit`/`sync`/`rebase`, bottom-up merge |

For each agent you select, `setup` installs a skill when missing and updates it when already present:

- Install: `gh skill install <repo> <skill> --agent <id> --scope user`
- Update: `gh skill update <skill>`

This step is skipped automatically on versions of `gh` too old to ship the `gh skill` command (a preview feature), and for Kimi Code, which this repo has no `gh skill --agent` id mapped for. To manage the skills yourself:

```bash
gh skill install cli/cli gh --agent claude-code --scope user               # install for one agent
gh skill install github/gh-stack gh-stack --agent claude-code --scope user
gh skill update gh                                                         # update (all hosts where it's installed)
gh skill list --agent claude-code                                          # verify
```

There is no `gh skill uninstall` command; to remove one, delete the installed skill directory (its location is agent-dependent, e.g. `~/.codex/skills/gh/` or `~/.copilot/skills/gh-stack/`; run `gh skill list --json skillName,path` to see the exact filesystem path).

## Stacked Pull Requests

[Stacked PRs](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs) are a chain of dependent branches where each pull request targets the one below it instead of `main`, so each layer stays small and reviewable and the stack merges bottom-up. GitHub drives them through the official [`gh stack`](https://github.com/github/gh-stack) extension.

`setup` offers the extension once per run (it is agent-agnostic, unlike the skills above), installing it when missing and upgrading it when already present:

```bash
gh extension install github/gh-stack   # install
gh extension upgrade gh-stack          # update
```

Pair it with the `gh-stack` agent skill above so your agent knows the workflow. The core loop:

```bash
gh stack init          # start a stack on the current repo, naming the first branch
gh stack add NAME      # add the next layer on top (-Am "msg" also stages and commits)
gh stack push          # push every branch in the stack
gh stack submit        # create/update the PRs and link them as a stack
gh stack view          # show the branches, PR links, and commits
gh stack sync          # fetch, rebase, push, and sync PR state after main moves
gh stack merge         # merge one or more PRs, bottom-up
```

`gh stack up`/`down`/`top`/`bottom`/`trunk` move between layers. See the [CLI command reference](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands) for every subcommand and flag. Cross-fork stacks and GitHub Desktop are not supported.

## Impeccable Design Skills

`setup` can also install [Impeccable](https://impeccable.style), a **third-party** design skill set for AI coding agents. It gives your agent a shared design vocabulary and commands (typography, color, motion, layout, polish, and AI-slop detection), with a build tailored to each harness. It is unrelated to the commands this repo ships.

For the selected tools it supports (Claude Code, Codex CLI, Copilot CLI), `setup` offers to run one command covering them all:

```bash
npx impeccable install --providers=claude,codex,github --scope=global
```

Because it runs via `npx` (always the latest) with explicit `--providers`/`--scope`, re-running `setup` and accepting this step refreshes an existing install and adds any newly-selected agents. There is no separate detect-and-update branch (unlike the `gh` skill above), since `install` with explicit providers is already idempotent and provider-aware.

Antigravity CLI and Kimi Code CLI have no Impeccable provider, so they are skipped. This step needs `npx` (Node.js). To manage Impeccable yourself:

```bash
npx impeccable install --providers=claude --scope=global   # install for one provider
npx impeccable update                                       # update
```

See [impeccable.style](https://impeccable.style) for the full command list and the Claude Code plugin install (`/plugin marketplace add pbakaus/impeccable`).

## Adding New Commands

Commands are authored once as Claude Code command files; everything else is generated:

1. Create `.claude/commands/command-name.md`, markdown with YAML front matter containing at least `description` (plus optional Claude-specific keys like `allowed-tools` or `argument-hint`), and an optional `$ARGUMENTS` placeholder in the body.
2. If the command should also ship as a Codex/Copilot/Antigravity/Kimi skill, add its name to `SKILL_COMMANDS` in `tools/generate` (or `PROMPT_COMMANDS` if the review loops need it as a shared prompt).
3. Run `tools/generate` to produce the derived `SKILL.md` and prompt files, and commit them together with the source.

Run `./setup` again to install.

### Prompt style

These commands target current-generation models, which follow intent better than
procedure. Anthropic's [new rules of context engineering][ctx] are the house
style here:

- **Put the trigger in the `description`.** It is the only text a model sees
  before deciding to load the skill, so say *when* to reach for it, and when to
  reach for a sibling instead, not just what it does.
- **Say it once.** If the body opens by restating the `description`, delete that
  line. Guidance belongs in exactly one place.
- **Spend tokens on gotchas, not procedure.** Skip steps a competent model
  already knows (how to read a diff hunk, how to subtract two dates). Keep the
  things it cannot infer: the `--slurp` / `--jq` conflict in `gh api`, an empty
  staged diff that still has staged files, which install hooks run automatically.
- **Frame outcomes, not rules.** "Match the surrounding code" beats a list of
  banned constructs. Reserve hard constraints for the places where breaking them
  breaks something: the review loops really do depend on the exact
  `NO_FURTHER_FEEDBACK` sentinel and on the reviewer never touching source files.
- **Keep rubrics and output templates.** Structured criteria and worked report
  formats are references the model fills in, not rules that box it in.

[ctx]: https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models

## Uninstalling

Delete the command/skill from the corresponding directory (or uninstall the plugin for Antigravity):

- Claude: `~/.claude/commands/` (agents: `~/.claude/agents/`)
- Codex: `~/.codex/skills/`
- Copilot: `~/.copilot/skills/`
- Antigravity: Run `agy plugin uninstall ai-coding-setup`
- Kimi Code: `~/.kimi-code/skills/` (or `$KIMI_CODE_HOME/skills/`)

If you installed the review gate hook, remove its `PreToolUse` entry from `~/.claude/settings.json` and delete `~/.local/bin/review-gate`. Per-repository state under `.git/ai-review/` can go too; nothing else reads it.

The setup script only manages commands it originally installed. The upstream extras are removed separately: `gh extension remove gh-stack` for the `gh stack` extension, and for the `gh`/`gh-stack` agent skills, delete their directories as described in [`gh` Agent Skills](#gh-agent-skills).

## Contributing

### Running Tests

The test suite uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System). After cloning with submodules:

```bash
git clone --recurse-submodules https://github.com/rlorenzo/ai-coding-setup.git
cd ai-coding-setup
test/run
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
test/run
```

Unit tests (`test/run`) cover config parsing, prompt loading, validation, review status checks, and generated-file sync. They run in seconds and need no API keys.

If you edit a command source in `.claude/commands/`, run `tools/generate` afterwards; the test suite and pre-commit both fail when the derived skill/prompt files are stale.

### Smoke Tests

Smoke tests run real AI agents against a temporary git repo to verify that CLI flags are accepted and agents can perform basic read/write tasks:

```bash
test/smoke                   # test all installed agents
test/smoke claude codex      # test specific agents
test/smoke --timeout 180     # override per-test timeout (default: 120s)
```

Each installed agent is tested as both editor (can it modify a file?) and reviewer (does it produce a review file?). Requires at least one AI tool installed and authenticated.

### Pre-commit hooks (optional)

This repo uses [pre-commit](https://pre-commit.com/) to run linters locally before each commit. Install it once and you'll get automatic checks for shell scripts (shellcheck), markdown (markdownlint), TOML syntax, the BATS suite, and a SkillSpector security scan of the skills this repo publishes.

Because of that last one the hook environment needs Python 3.12, 3.13, or 3.14. If yours is outside that range, pre-commit fails while building the hook's venv; `SKIP=skillspector-skills,skillspector-agent git commit ...` gets you past it, and CI runs the scan either way.

```bash
pip install pre-commit   # or: brew install pre-commit (macOS)
pre-commit install
```

After that, hooks run automatically on `git commit`. You can also run them manually:

```bash
pre-commit run --all-files
```

If you skip the local setup, the same checks run in CI on your pull request.

### Skill security scanning

The skills in this repo are meant to be installed into other people's agents, where they run with whatever trust that agent has. [SkillSpector](https://github.com/NVIDIA/skillspector), NVIDIA's security scanner for agent skills, checks them for prompt injection, hidden instructions, data exfiltration, tool misuse, and supply-chain risk before they leave here.

Two pre-commit hooks run it, and the `Lint` workflow runs every pre-commit hook over every file, so the scan gates pull requests too. There is no separate security workflow.

- It runs with `--no-llm`, the static analyzers only. The semantic ones want an API key that neither a laptop nor CI has, and SkillSpector skips them with a warning rather than failing.
- The gate is the exit code: `0` for `SAFE` or `CAUTION`, `1` for `DO_NOT_INSTALL` (a risk score above 50), `2` for an error. Only a genuinely bad score blocks a commit. The `CAUTION` findings print and let you through, which is the intent: `git-history-cleanup` scores 25 for the `git reset --hard` and `--force-with-lease` in its own instructions, and a skill about rewriting history is going to mention rewriting history.
- The dependency is pinned to the commit behind `v2.11.0`. SkillSpector is not on PyPI, so it installs from a git URL, and a tag can be moved where a commit cannot.
- Only the Codex copies of the skills are scanned. `tools/generate` renders every harness from the canonical `.claude/commands/` sources and the `generated-files-in-sync` hook proves they match, so the bodies are byte-identical and scanning four copies would buy three more runs and nothing else.
- `.claude/agents/` is not a skill directory, so the second hook names its files directly. The scanner takes one path per run, so each agent needs its own hook; `test/skillspector-hooks.bats` fails if one is added without one.

To run it by hand:

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git@v2.11.0
skillspector scan .codex/skills --recursive --no-llm
```

## License

MIT
