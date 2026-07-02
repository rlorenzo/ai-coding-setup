# ai-coding-setup

Set of prompts, skills, and scripts to aid in utilizing AI coding agents in development workflows.

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) 2.88.0+, installed and authenticated (`/review-pr` uses `gh pr edit --add-reviewer` to reliably re-request reviews from existing bot reviewers)
- [Node.js (`npx`)](https://nodejs.org/), required for MCP servers
- At least one of the following AI coding tools:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli)
  - [Codex CLI](https://github.com/openai/codex)
  - [Copilot CLI](https://docs.github.com/en/copilot/copilot-cli)
  - Antigravity CLI (using the `agy` command)

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
| Gemini CLI | TOML (`.toml`) | `.gemini/commands/` | `~/.gemini/commands/` |
| Codex CLI | Agent Skills (`SKILL.md`) | `.codex/skills/` | `~/.codex/skills/` |
| Copilot CLI | Agent Skills (`SKILL.md`) | `.copilot/skills/` | `~/.copilot/skills/` |
| Antigravity CLI | Unified Plugin (`plugin.json`) | `.antigravity/` | `~/.gemini/antigravity-cli/plugins/ai-coding-setup/` |
| Shared prompts | Markdown (`.md`) | `prompts/` | `~/.local/share/ai-coding-setup/prompts/` |

## Available Commands

### /commitmsg

Propose a conventional commit message for the currently staged changes. Detects ticket IDs from branch names and follows the project's recent commit style.

**Usage:**

- Claude Code: `/commitmsg`
- Gemini CLI: `/commitmsg`
- Codex CLI: `$commitmsg`
- Copilot CLI: `/commitmsg`
- Antigravity CLI: `/commitmsg`

### /review-pr

Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review.

**Usage:**

- Claude Code: `/review-pr [PR_NUMBER]`
- Gemini CLI: `/review-pr [PR_NUMBER]`
- Codex CLI: `$review-pr [PR_NUMBER]`
- Copilot CLI: `/review-pr [PR_NUMBER]`
- Antigravity CLI: `/review-pr [PR_NUMBER]`

### /code-refinement

Review staged files for code quality (KISS, DRY, YAGNI, Clean Code), fix linting issues, and check test coverage.

**Usage:**

- Claude Code: `/code-refinement`
- Gemini CLI: `/code-refinement`
- Codex CLI: `$code-refinement`
- Copilot CLI: `/code-refinement`
- Antigravity CLI: `/code-refinement`

### /code-review

Run a standalone code review on staged changes. Writes findings to `agent-code-review.md`.

**Usage:**

- Claude Code: `/code-review`
- Gemini CLI: `/code-review`
- Codex CLI: `$code-review`
- Copilot CLI: `/code-review`
- Antigravity CLI: `/code-review`

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

Supported agents: `claude`, `codex`, `gemini`, `copilot`, `antigravity`. Only the agents you actually have installed need to be referenced.

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

- Each AI tool has its own command format, so commands are maintained as separate source files per tool.
- The `setup` script copies selected commands to the appropriate user-level directory for each tool.
- Shared prompts are installed to `~/.local/share/ai-coding-setup/prompts/` and referenced by the review loop scripts.
- Installed commands are tagged with a source marker so the script can safely update them later without overwriting your custom commands that happen to share the same name.

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

## Adding New Commands

To add a command, create the appropriate file(s) for each tool you want to support:

1. **Claude Code**: create `.claude/commands/command-name.md` (markdown with `$ARGUMENTS` placeholder)
2. **Gemini CLI**: create `.gemini/commands/command-name.toml` (TOML with `description` and `prompt` fields, `{{args}}` placeholder)
3. **Codex CLI**: create `.codex/skills/command-name/SKILL.md` (markdown with YAML front matter containing `name` and `description`)
4. **Copilot CLI**: create `.copilot/skills/command-name/SKILL.md` (same format as Codex skills)
5. **Antigravity CLI**: create `.antigravity/skills/command-name/SKILL.md` (same format as Codex/Copilot skills)

Run `./setup` again to install.

## Uninstalling

Delete the command/skill from the corresponding directory (or uninstall the plugin for Antigravity):

- Claude: `~/.claude/commands/`
- Gemini: `~/.gemini/commands/`
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

Unit tests (`test/run`) cover config parsing, prompt loading, validation, and review status checks. They run in seconds and need no API keys.

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
