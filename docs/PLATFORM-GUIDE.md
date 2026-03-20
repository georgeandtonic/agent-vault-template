# Platform Guide

This template supports multiple agent ecosystems, but they do not all use the same file format.

## OpenClaw

Use OpenClaw when the user wants workspace-oriented agent instructions and persistent operational files.

- Primary scaffold: `AGENTS.md`
- Typical workspace home: `~/openclaw agents/workspaces/<agent-name>/`
- Recommended use: durable specialist workspaces with explicit roles and boundaries

## Claude Code

Claude Code subagents are Markdown files with YAML frontmatter.

- Project scope: `.claude/agents/`
- User scope: `~/.claude/agents/`
- Required fields: `name`, `description`
- Optional fields: `tools`, `model`

## Codex Skills

Codex-style reusable specializations are best represented as skill folders containing `SKILL.md`.

- Typical location: `~/.codex/skills/<skill-name>/`
- Required structure: one folder per skill, each with a `SKILL.md`
- Recommended use: reusable workflow instructions that trigger when the task matches the skill description

## ChatGPT Custom GPTs

ChatGPT does not use a local filesystem subagent format in the same way. Instead, the installer generates source material for the GPT Builder.

- Builder location: `chatgpt.com/gpts/editor`
- Installer output: a Markdown file containing name, description, instructions, and conversation starters
- Recommended use: user-facing assistants that rely on builder configuration and uploaded knowledge files

## Selection Rule

Choose the format that matches the runtime:

- If the user runs OpenClaw, generate `AGENTS.md` workspaces.
- If the user runs Claude Code, generate `.md` files with YAML frontmatter.
- If the user runs Codex-compatible skills, generate `SKILL.md` folders.
- If the user uses ChatGPT GPTs, generate GPT builder content rather than pretending there is a deployable local subagent file.
