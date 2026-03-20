# Agent Vault Template

A starter vault plus guided setup flow for building a personal AI working environment.

This repository gives users:

- a blank vault structure
- a first-run installer
- platform-aware agent templates for OpenClaw, Claude Code, Codex-style skills, and ChatGPT custom GPTs
- a tutorial project that helps them connect the systems they actually use

## Recommended Setup

1. Create a new repository from this template on GitHub.
2. Clone it locally, ideally somewhere under `~/Documents`.
3. Run:

```bash
./install.sh
```

The installer will:

- explain what the vault is for
- ask which agent platform(s) the user wants to use
- ask for two workflows to turn into starter agents
- scaffold platform-specific agent definitions in the right format
- create a tutorial project for connecting tools and finishing setup

## What Gets Created

- core vault folders
- `90 Ops/First Run.md`
- `01 Projects/Agent Setup Tutorial/`
- `90 Ops/Agents/` with source templates for the chosen platforms
- optional live installs for Claude Code, OpenClaw, and Codex-compatible skills

## Platform Notes

- OpenClaw: workspace-oriented `AGENTS.md` scaffolds
- Claude Code: `.claude/agents/*.md` subagents with YAML frontmatter
- Codex: skill folders containing `SKILL.md`
- ChatGPT: custom GPT builder instructions and conversation starters

See [`docs/FIRST-RUN.md`](/Users/george/Documents/agent-vault-template/docs/FIRST-RUN.md) and [`docs/PLATFORM-GUIDE.md`](/Users/george/Documents/agent-vault-template/docs/PLATFORM-GUIDE.md) for more detail.
