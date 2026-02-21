# ai-coding-setup

Set of prompts, skills, and scripts to aid in utilizing AI coding agents in development workflows.

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) — installed and authenticated
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

## How It Works

- Each AI tool has its own command format, so commands are maintained as separate source files per tool.
- The `setup` script copies selected commands to the appropriate user-level directory for each tool.
- Installed commands are tagged with a source marker so the script can safely update them later without overwriting your custom commands that happen to share the same name.

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

## License

MIT
