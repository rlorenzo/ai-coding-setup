# ai-coding-setup

Set of prompts, skills, and scripts to aid in utilizing AI coding agents in development workflows.

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) — installed and authenticated
- [Node.js (`npx`)](https://nodejs.org/) — required for MCP servers
- At least one of the following AI coding tools:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli)
  - [Codex CLI](https://github.com/openai/codex)

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

## Available Commands

### /review-pr

Process unresolved review comments on a GitHub PR, fix valid issues, ensure CI passes, and re-request review.

**Usage:**

- Claude Code: `/review-pr [PR_NUMBER]`
- Gemini CLI: `/review-pr [PR_NUMBER]`
- Codex CLI: `$review-pr [PR_NUMBER]`

### /commitmsg

Propose a conventional commit message for the currently staged changes. Detects ticket IDs from branch names and follows the project's recent commit style.

**Usage:**

- Claude Code: `/commitmsg`
- Gemini CLI: `/commitmsg`
- Codex CLI: `$commitmsg`

## How It Works

- Each AI tool has its own command format, so commands are maintained as separate source files per tool.
- The `setup` script copies selected commands to the appropriate user-level directory for each tool.
- Installed commands are tagged with a source marker so the script can safely update them later without overwriting your custom commands that happen to share the same name.

## MCP Server Configuration

The setup script can configure [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) servers for your AI tools. Currently supported:

| Server | Package | Description |
| --- | --- | --- |
| [Playwright](https://github.com/microsoft/playwright-mcp) | `@playwright/mcp@latest` | Browser automation and web testing |

MCP servers are added via each tool's `mcp add` CLI command at user scope.

## Adding New Commands

To add a command, create the appropriate file(s) for each tool you want to support:

1. **Claude Code** — create `.claude/commands/command-name.md` (markdown with `$ARGUMENTS` placeholder)
2. **Gemini CLI** — create `.gemini/commands/command-name.toml` (TOML with `description` and `prompt` fields, `{{args}}` placeholder)
3. **Codex CLI** — create `.codex/skills/command-name/SKILL.md` (markdown with YAML front matter containing `name` and `description`)

Run `./setup` again to install.

## Uninstalling

Delete the command/skill from the corresponding directory:

- Claude: `~/.claude/commands/`
- Gemini: `~/.gemini/commands/`
- Codex: `~/.codex/skills/`

The setup script only manages commands it originally installed.

## Contributing

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
