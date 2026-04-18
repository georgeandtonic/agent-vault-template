# Agent Vault Template

A starter vault for building a personal AI working environment with Claude Code.

## Setup

Clone this repo, then run the installer:

```bash
./install.sh
```

No prompts. The vault is created at `~/Documents/agent-vault`.

## What Gets Created

```
~/Documents/agent-vault/
  00 Inbox/
  01 Projects/
  02 Areas/
  03 Resources/
  04 Archive/
  90 Ops/Agents/Claude Code/
  91 Templates/
  92 Dashboards/
  93 Attachments/
  .claude/agents/
  .mcp.json          ← placeholder MCP config (gitignored)
  .gitignore
  CLAUDE.md
  HEARTBEAT.md
```

## MCP Configuration

`.mcp.json` is written with placeholder entries for **Atlassian**, **Slack**, and **GitHub**.

- **Atlassian** uses OAuth — no token needed. A browser window opens on first use.
- **Slack** requires a bot token (`SLACK_BOT_TOKEN`) and team ID (`SLACK_TEAM_ID`).
- **GitHub** requires a personal access token (`GITHUB_PERSONAL_ACCESS_TOKEN`).

Fill in the values before using those tools. The file is gitignored so credentials stay local.

## Vault Structure

| Folder | Purpose |
|--------|---------|
| `00 Inbox/` | Unclassified incoming material |
| `01 Projects/` | Active project folders |
| `02 Areas/` | Ongoing responsibilities |
| `03 Resources/` | Reusable reference material |
| `04 Archive/` | Finished or inactive work |
| `90 Ops/` | Agent configs and operating docs |
| `91 Templates/` | Reusable templates |

Each project folder follows the same shape: `project.md`, `tasks.md`, `log.md`, `decisions.md`, `meetings/`, `artifacts/`.
