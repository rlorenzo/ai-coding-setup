# ai-coding-setup

Set of prompts, skills, and scripts to aid in utilizing AI coding agents in development workflows.

## Prerequisites

The `setup` script and the review loops are Bash scripts that shell out to a handful of command-line tools. Install the ones below and make sure they are on your `PATH`.

**Required** (the `setup` script exits early if any is missing):

- [`git`](https://git-scm.com/), to clone the repo and drive the `git`-based commands
- [GitHub CLI (`gh`)](https://cli.github.com/) 2.88.0+, installed and authenticated (`/review-pr` uses `gh pr edit --add-reviewer` to reliably re-request reviews from existing bot reviewers)
- [`jq`](https://jqlang.github.io/jq/), a JSON processor used to read and edit each tool's settings and MCP config files

**Required only for optional steps:**

- [Node.js (`npx`)](https://nodejs.org/), for the MCP servers and the Impeccable design skills. `setup` skips those steps with a warning if `npx` is not found.

**At least one AI coding tool:**

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Codex CLI](https://github.com/openai/codex)
- [Copilot CLI](https://docs.github.com/en/copilot/copilot-cli)
- Antigravity CLI (using the `agy` command)

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
| Codex CLI | Agent Skills (`SKILL.md`) | `.codex/skills/` | `~/.codex/skills/` |
| Copilot CLI | Agent Skills (`SKILL.md`) | `.copilot/skills/` | `~/.copilot/skills/` |
| Antigravity CLI | Unified Plugin (`plugin.json`) | `.antigravity/` | `~/.gemini/antigravity-cli/plugins/ai-coding-setup/` |
| Shared prompts | Markdown (`.md`) | `prompts/` | `~/.local/share/ai-coding-setup/prompts/` |

## Available Commands

### /commitmsg

Propose a conventional commit message for the currently staged changes. Detects ticket IDs from branch names and follows the project's recent commit style.

**Usage:**

- Claude Code: `/commitmsg`
- Codex CLI: `$commitmsg`
- Copilot CLI: `/commitmsg`
- Antigravity CLI: `/commitmsg`

### /review-pr

Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review.

**Usage:**

- Claude Code: `/review-pr [PR_NUMBER]`
- Codex CLI: `$review-pr [PR_NUMBER]`
- Copilot CLI: `/review-pr [PR_NUMBER]`
- Antigravity CLI: `/review-pr [PR_NUMBER]`

### /code-refinement

Review staged files for code quality (KISS, DRY, YAGNI, Clean Code), fix linting issues, and check test coverage.

**Usage:**

- Claude Code: `/code-refinement`
- Codex CLI: `$code-refinement`
- Copilot CLI: `/code-refinement`
- Antigravity CLI: `/code-refinement`

### /code-review

Run a standalone code review on staged changes. Writes findings to `agent-code-review.md`.

**Usage:**

- Claude Code: `/code-review`
- Codex CLI: `$code-review`
- Copilot CLI: `/code-review`
- Antigravity CLI: `/code-review`

### /dependency-review

Audit dependency updates for supply-chain risk before they land: publish-age gate, changelog/diff verification, security advisories, community signals, and breaking changes.

**Usage:**

- Claude Code: `/dependency-review`
- Codex CLI: `$dependency-review`
- Copilot CLI: `/dependency-review`
- Antigravity CLI: `/dependency-review`

### /efficient-orchestration

Run a task with your current model as the orchestrator and reviewer while cheaper, faster subagents do the token-heavy research, coding, and testing. It matches model tier to task difficulty (your own tier for complex work, a mid tier for low/medium, the cheapest tier for mechanical), keeps the orchestrator's own reading and searching lean, runs delegation in bounded waves to respect your usage caps, and for long unattended runs auto-pauses and resumes across usage windows. No model names are hardcoded beyond a Claude example ladder: each harness orders its own available models by cost and capability, and everything else is written relative to whatever tier you are on. Agents without a native subagent tool (Codex, Copilot) delegate by spawning their own CLI non-interactively with an explicit model.

**Usage:**

- Claude Code: `/efficient-orchestration`
- Codex CLI: `$efficient-orchestration`
- Copilot CLI: `/efficient-orchestration`
- Antigravity CLI: `/efficient-orchestration`

## Review Loops

Two multi-agent feedback loops live in [bin/](bin/): `code-review-loop` (for staged code) and `plan-review-loop` (for plan documents). Each loop pairs an **editor** agent with a different **reviewer** agent and iterates until the reviewer is satisfied or `--max-iterations` is hit. Using two different models for editing and reviewing surfaces issues a single agent tends to miss in its own output.

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

### Configuration

Defaults are `--editor claude --reviewer codex`. Override per-run with `-e` / `-r`, or persist defaults in `~/.ai-coding-setup.conf`:

```ini
EDITOR_AGENT=claude
REVIEWER_AGENT=codex
```

Supported agents: `claude`, `codex`, `copilot`, `antigravity`. Only the agents you actually have installed need to be referenced.

Both loops write their working files (`agent-code-review.md`, `agent-review-summary.md`, `feedback-plan.md`, `plan-review-summary.md`) to the target project's root. Consider adding those names to that project's `.gitignore` (or your global gitignore) so an agent never commits them by accident.

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

- Each AI tool has its own command format, but the content is maintained once: `.claude/commands/*.md` files are the canonical sources, and `tools/generate` derives the Codex/Copilot/Antigravity `SKILL.md` files and the shared loop prompts from them. A pre-commit/CI check (`tools/generate --check`) fails if the derived files drift from their sources.
- The `setup` script copies selected commands to the appropriate user-level directory for each tool.
- Shared prompts are installed to `~/.local/share/ai-coding-setup/prompts/` and referenced by the review loop scripts.
- Installed commands are tagged with a source marker so the script can safely update them later without overwriting your custom commands that happen to share the same name.
- On each run the script also offers to prune stale installs: any command it previously installed (identified by that same marker) that no longer exists in the repo can be removed, so renamed or deleted commands clean themselves up. It asks before each removal (default No, so nothing is dropped without your say-so), or pass `--force` to prune without prompting. Your own unmarked commands are never touched.

## MCP Server Configuration

The setup script can configure [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) servers for your AI tools. Currently supported:

| Server | Package | Description |
| --- | --- | --- |
| [Playwright](https://github.com/microsoft/playwright-mcp) | `@playwright/mcp@latest` | Browser automation and web testing |

MCP servers are added via each tool's `mcp add` CLI command at user scope.

## `gh` Agent Skill

Beyond the commands in this repo, `setup` can install the [`gh` agent skill published by `cli/cli`](https://github.com/cli/cli#agent-skills) for each selected tool. This is an **upstream** skill from the GitHub CLI team that teaches an agent to drive `gh` well — structured JSON output, pagination, repo targeting, search vs. list, and `gh api` fallback. It is unrelated to the commands/skills this repo ships.

For each agent you select, `setup` installs it when missing and updates it when already present:

- Install — `gh skill install cli/cli gh --agent <id> --scope user`
- Update — `gh skill update gh`

This step is skipped automatically on versions of `gh` too old to ship the `gh skill` command (a preview feature). To manage it yourself:

```bash
gh skill install cli/cli gh --agent claude-code --scope user   # install for one agent
gh skill update gh                                             # update (all hosts where it's installed)
gh skill list --agent claude-code                              # verify
```

There is no `gh skill uninstall` command; to remove it, delete the installed `gh/` skill directory (its location is agent-dependent — e.g. `~/.codex/skills/gh/` or `~/.copilot/skills/gh/`; run `gh skill list --json skillName,path` to see the exact filesystem path).

## Impeccable Design Skills

`setup` can also install [Impeccable](https://impeccable.style), a **third-party** design skill set for AI coding agents. It gives your agent a shared design vocabulary and commands (typography, color, motion, layout, polish, and AI-slop detection), with a build tailored to each harness. It is unrelated to the commands this repo ships.

For the selected tools it supports (Claude Code, Codex CLI, Copilot CLI), `setup` offers to run one command covering them all:

```bash
npx impeccable install --providers=claude,codex,github --scope=global
```

Because it runs via `npx` (always the latest) with explicit `--providers`/`--scope`, re-running `setup` and accepting this step refreshes an existing install and adds any newly-selected agents. There is no separate detect-and-update branch (unlike the `gh` skill above), since `install` with explicit providers is already idempotent and provider-aware.

Antigravity CLI has no Impeccable provider, so it is skipped. This step needs `npx` (Node.js). To manage Impeccable yourself:

```bash
npx impeccable install --providers=claude --scope=global   # install for one provider
npx impeccable update                                       # update
```

See [impeccable.style](https://impeccable.style) for the full command list and the Claude Code plugin install (`/plugin marketplace add pbakaus/impeccable`).

## Adding New Commands

Commands are authored once as Claude Code command files; everything else is generated:

1. Create `.claude/commands/command-name.md` — markdown with YAML front matter containing at least `description` (plus optional Claude-specific keys like `allowed-tools` or `argument-hint`), and an optional `$ARGUMENTS` placeholder in the body.
2. If the command should also ship as a Codex/Copilot/Antigravity skill, add its name to `SKILL_COMMANDS` in `tools/generate` (or `PROMPT_COMMANDS` if the review loops need it as a shared prompt).
3. Run `tools/generate` to produce the derived `SKILL.md` and prompt files, and commit them together with the source.

Run `./setup` again to install.

## Uninstalling

Delete the command/skill from the corresponding directory (or uninstall the plugin for Antigravity):

- Claude: `~/.claude/commands/`
- Codex: `~/.codex/skills/`
- Copilot: `~/.copilot/skills/`
- Antigravity: Run `agy plugin uninstall ai-coding-setup`

The setup script only manages commands it originally installed.

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

If you edit a command source in `.claude/commands/`, run `tools/generate` afterwards — the test suite and pre-commit both fail when the derived skill/prompt files are stale.

### Smoke Tests

Smoke tests run real AI agents against a temporary git repo to verify that CLI flags are accepted and agents can perform basic read/write tasks:

```bash
test/smoke                   # test all installed agents
test/smoke claude codex      # test specific agents
test/smoke --timeout 180     # override per-test timeout (default: 120s)
```

Each installed agent is tested as both editor (can it modify a file?) and reviewer (does it produce a review file?). Requires at least one AI tool installed and authenticated.

### Pre-commit hooks (optional)

This repo uses [pre-commit](https://pre-commit.com/) to run linters locally before each commit. Install it once and you'll get automatic checks for shell scripts (shellcheck), markdown (markdownlint), and TOML syntax.

```bash
pip install pre-commit   # or: brew install pre-commit (macOS)
pre-commit install
```

After that, hooks run automatically on `git commit`. You can also run them manually:

```bash
pre-commit run --all-files
```

If you skip the local setup, the same checks run in CI on your pull request.

## License

MIT
