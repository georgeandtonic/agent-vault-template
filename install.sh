#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# ─────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────

VAULT_DIR="$HOME/Documents/agent-vault"
TODAY="$(date +%Y-%m-%d)"

# ─────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────

ensure_dir() { mkdir -p "$1"; }

# ─────────────────────────────────────────────────────────────
# BEGIN SETUP
# ─────────────────────────────────────────────────────────────

printf "┌──────────────────────────────────────────┐\n"
printf "│           Agent Vault Setup              │\n"
printf "└──────────────────────────────────────────┘\n"
echo
echo "Creating vault at: $VAULT_DIR"
echo

# ── Vault structure ───────────────────────────────────────────

VAULT_DIRS=(
  "00 Inbox"
  "01 Projects"
  "02 Areas"
  "03 Resources"
  "04 Archive"
  "90 Ops/Agents/Claude Code"
  "91 Templates"
  "92 Dashboards"
  "93 Attachments"
  ".claude/agents"
)
for d in "${VAULT_DIRS[@]}"; do
  ensure_dir "$VAULT_DIR/$d"
done

# ── Static files ──────────────────────────────────────────────

for f in CLAUDE.md HEARTBEAT.md "Vault Home.md"; do
  [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$VAULT_DIR/$f"
done

[[ -d "$TEMPLATES_DIR" ]] && cp -r "$TEMPLATES_DIR" "$VAULT_DIR/"

# ── .gitignore ────────────────────────────────────────────────

cat > "$VAULT_DIR/.gitignore" <<'GITIGNORE'
# MCP config may contain credentials — do not commit
.mcp.json

# macOS
.DS_Store

# Keys and certificates
*.key
*.pem
*.crt
*.csr
GITIGNORE

# ── .mcp.json (placeholders) ──────────────────────────────────

cat > "$VAULT_DIR/.mcp.json" <<'MCPJSON'
{
  "mcpServers": {
    "Atlassian": {
      "command": "npx",
      "args": ["mcp-remote@latest", "https://mcp.atlassian.com/v1/mcp"]
    },
    "Slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "YOUR_SLACK_BOT_TOKEN",
        "SLACK_TEAM_ID": "YOUR_SLACK_TEAM_ID"
      }
    },
    "GitHub": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN"
      }
    }
  }
}
MCPJSON

echo ".mcp.json written with placeholders for Atlassian, Slack, and GitHub."
echo "Edit it to fill in your credentials before using those tools."
echo

# ── Git init ──────────────────────────────────────────────────

if ! git -C "$VAULT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$VAULT_DIR" init -b main
  git -C "$VAULT_DIR" add .
  git -C "$VAULT_DIR" commit -m "Initial vault setup"
  echo "Git repository initialized."
else
  echo "Git repository already exists — skipping init."
fi

# ── Done ──────────────────────────────────────────────────────

echo
printf "┌──────────────────────────────────────────┐\n"
printf "│           Setup Complete                 │\n"
printf "└──────────────────────────────────────────┘\n"
echo
printf "Vault: %s\n" "$VAULT_DIR"
echo
echo "Next steps:"
echo "  1. Open Claude Code with the vault folder as the project root."
echo "  2. Fill in credentials in .mcp.json to connect Slack and GitHub."
echo "     (Atlassian uses OAuth — no token needed upfront.)"
echo
