#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# ─────────────────────────────────────────────────────────────
# Terminal helpers
# ─────────────────────────────────────────────────────────────

section() {
  echo
  echo "────────────────────────────────────────"
  echo "  $1"
  echo "────────────────────────────────────────"
  echo
}

prompt_default() {
  local label="$1" default="$2" value
  read -r -p "$label [$default]: " value
  printf '%s' "${value:-$default}"
}

prompt_required() {
  local label="$1" value=""
  while [[ -z "$value" ]]; do
    read -r -p "$label: " value
  done
  printf '%s' "$value"
}

prompt_yes_no() {
  local label="$1" default="${2:-y}" value
  read -r -p "$label [${default}]: " value
  value="${value:-$default}"
  [[ "$value" =~ ^[Yy] ]]
}

prompt_secret() {
  local label="$1" value=""
  while [[ -z "$value" ]]; do
    read -r -s -p "$label: " value
    echo
  done
  printf '%s' "$value"
}

# ─────────────────────────────────────────────────────────────
# Multi-select: arrow keys to navigate, space to toggle, enter to confirm
# Usage: multiselect RESULT_VAR "Option 1" "Option 2" ...
#        RESULT_VAR becomes an array of selected option strings
# ─────────────────────────────────────────────────────────────

_ms_cursor=0
_ms_count=0
_ms_selected=()
_ms_options=()

_ms_draw() {
  local i
  for ((i=0; i<_ms_count; i++)); do
    local pre="  " mark="[ ]"
    [[ $i -eq $_ms_cursor ]] && pre=" >"
    [[ ${_ms_selected[$i]} -eq 1 ]] && mark="[x]"
    printf "\r%s %s  %s\n" "$pre" "$mark" "${_ms_options[$i]}"
  done
  # Move cursor back to top of list
  printf "\033[%dA" "$_ms_count"
}

multiselect() {
  local result_var="$1"
  shift
  _ms_options=("$@")
  _ms_count=${#_ms_options[@]}
  _ms_cursor=0
  _ms_selected=()

  local i
  for ((i=0; i<_ms_count; i++)); do _ms_selected[$i]=0; done

  tput civis 2>/dev/null || true
  _ms_draw

  while true; do
    local key seq
    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn2 -t 0.1 seq || seq=""
      case "$seq" in
        '[A') ((_ms_cursor > 0)) && ((_ms_cursor--)) || true ;;
        '[B') ((_ms_cursor < _ms_count - 1)) && ((_ms_cursor++)) || true ;;
      esac
    elif [[ "$key" == ' ' ]]; then
      if [[ ${_ms_selected[$_ms_cursor]} -eq 0 ]]; then
        _ms_selected[$_ms_cursor]=1
      else
        _ms_selected[$_ms_cursor]=0
      fi
    elif [[ "$key" == '' ]]; then
      break
    fi
    _ms_draw
  done

  # Move past the list and restore cursor
  printf "\033[%dB\n" "$_ms_count"
  tput cnorm 2>/dev/null || true

  # Write selected items to result variable
  local result=()
  for ((i=0; i<_ms_count; i++)); do
    [[ ${_ms_selected[$i]} -eq 1 ]] && result+=("${_ms_options[$i]}")
  done

  if [[ ${#result[@]} -gt 0 ]]; then
    eval "${result_var}=($(printf '"%s" ' "${result[@]}"))"
  else
    eval "${result_var}=()"
  fi
}

# ─────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/-\{2,\}/-/g' \
    | sed 's/^-//' \
    | sed 's/-$//'
}

trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'; }

ensure_dir() { mkdir -p "$1"; }

escape_sed() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

append_task() {
  printf -- "- [ ] %s\n" "$2" >> "$1"
}

write_from_template() {
  local template_path="$1" target_path="$2" agent_title="$3" agent_slug="$4"
  ensure_dir "$(dirname "$target_path")"
  sed \
    -e "s|__WORKFLOW_TITLE__|$(escape_sed "$agent_title")|g" \
    -e "s|__WORKFLOW_SLUG__|$(escape_sed "$agent_slug")|g" \
    -e "s|__USER_NAME__|$(escape_sed "$USER_NAME")|g" \
    -e "s|__VAULT_PATH__|$(escape_sed "$VAULT_DIR")|g" \
    "$template_path" > "$target_path"
}

# ─────────────────────────────────────────────────────────────
# MCP config builders
# ─────────────────────────────────────────────────────────────

MCP_ENTRIES=()

mcp_add_atlassian() {
  MCP_ENTRIES+=('    "Atlassian": {
      "command": "npx",
      "args": ["mcp-remote@latest", "https://mcp.atlassian.com/v1/mcp"]
    }')
}

mcp_add_notion() {
  MCP_ENTRIES+=('    "Notion": {
      "type": "http",
      "url": "https://mcp.notion.com/mcp"
    }')
}

mcp_add_salesforce() {
  local org_alias="$1"
  MCP_ENTRIES+=("    \"Salesforce\": {
      \"command\": \"npx\",
      \"args\": [\"-y\", \"@salesforce/mcp\", \"--orgs\", \"$org_alias\", \"--toolsets\", \"orgs,metadata,data,users\"]
    }")
}

mcp_add_slack() {
  local bot_token="$1" team_id="$2"
  MCP_ENTRIES+=("    \"Slack\": {
      \"command\": \"npx\",
      \"args\": [\"-y\", \"@modelcontextprotocol/server-slack\"],
      \"env\": {
        \"SLACK_BOT_TOKEN\": \"$bot_token\",
        \"SLACK_TEAM_ID\": \"$team_id\"
      }
    }")
}

mcp_add_github() {
  local token="$1"
  MCP_ENTRIES+=("    \"GitHub\": {
      \"command\": \"npx\",
      \"args\": [\"-y\", \"@modelcontextprotocol/server-github\"],
      \"env\": {
        \"GITHUB_PERSONAL_ACCESS_TOKEN\": \"$token\"
      }
    }")
}

write_mcp_json() {
  if [[ ${#MCP_ENTRIES[@]} -eq 0 ]]; then return; fi

  local out i
  out='{\n  "mcpServers": {\n'
  for ((i=0; i<${#MCP_ENTRIES[@]}; i++)); do
    out+="${MCP_ENTRIES[$i]}"
    [[ $i -lt $((${#MCP_ENTRIES[@]} - 1)) ]] && out+=","
    out+="\n"
  done
  out+='  }\n}'
  printf '%b' "$out" > "$VAULT_DIR/.mcp.json"
}

# ─────────────────────────────────────────────────────────────
# Tool setup wizards
# ─────────────────────────────────────────────────────────────

setup_atlassian() {
  echo "Atlassian connects to Jira and Confluence using OAuth."
  echo "No token is needed right now — when Claude first uses this tool,"
  echo "a browser window will open so you can log in to your Atlassian account."
  echo
  if ! command_exists npx; then
    echo "Note: npx (Node.js) is required. Install from https://nodejs.org"
  fi
  mcp_add_atlassian
  echo "Atlassian added."
}

setup_notion() {
  echo "Notion connects via OAuth."
  echo "When Claude first uses this tool it will prompt you to authenticate"
  echo "through your browser. No token needed right now."
  echo
  mcp_add_notion
  echo "Notion added."
}

setup_salesforce() {
  echo "Salesforce uses the Salesforce CLI to connect to your org."
  echo

  if ! command_exists sf && ! command_exists sfdx; then
    echo "Salesforce CLI not found on this machine."
    echo "Install it from: https://developer.salesforce.com/tools/salesforcecli"
    echo
    if ! prompt_yes_no "Configure Salesforce anyway (you can authenticate the CLI later)?" "y"; then
      echo "Skipping Salesforce."
      return
    fi
  else
    echo "Salesforce CLI found. Authenticated orgs:"
    sf org list --json 2>/dev/null \
      | grep '"alias"' \
      | sed 's/.*"alias": "\(.*\)".*/  - \1/' \
      || echo "  (none — run 'sf org login web' to authenticate)"
    echo
  fi

  local org_alias
  org_alias="$(prompt_required "Org alias to connect (e.g. production, staging, dev)")"
  mcp_add_salesforce "$org_alias"
  echo "Salesforce added with org: $org_alias"
}

setup_slack() {
  echo "Slack requires a Bot Token from a Slack app you create."
  echo
  echo "Steps:"
  echo "  1. Go to https://api.slack.com/apps → Create New App → From scratch"
  echo "  2. Under OAuth & Permissions, add these Bot Token Scopes:"
  echo "       channels:history  channels:read  chat:write"
  echo "       groups:read  im:read  mpim:read  users:read"
  echo "  3. Click 'Install to Workspace'"
  echo "  4. Copy the Bot User OAuth Token (starts with xoxb-)"
  echo "  5. Find your Team ID in workspace settings (starts with T)"
  echo
  local bot_token team_id
  bot_token="$(prompt_secret "Slack Bot Token (xoxb-...)")"
  team_id="$(prompt_required "Slack Team ID (T...)")"
  mcp_add_slack "$bot_token" "$team_id"
  echo "Slack added."
}

setup_github() {
  echo "GitHub requires a Personal Access Token."
  echo
  echo "Steps:"
  echo "  1. Go to https://github.com/settings/tokens"
  echo "  2. Generate new token (classic)"
  echo "  3. Select scopes: repo, read:org, read:user"
  echo "  4. Copy the token"
  echo
  local token
  token="$(prompt_secret "GitHub Personal Access Token (ghp_...)")"
  mcp_add_github "$token"
  echo "GitHub added."
}

# ─────────────────────────────────────────────────────────────
# Git / GitHub setup
# ─────────────────────────────────────────────────────────────

configure_git_identity() {
  local current_name current_email
  current_name="$(git -C "$VAULT_DIR" config user.name 2>/dev/null || true)"
  current_email="$(git -C "$VAULT_DIR" config user.email 2>/dev/null || true)"
  if [[ -z "$current_name" ]]; then
    current_name="$(prompt_default "Git user.name" "$USER_NAME")"
    git -C "$VAULT_DIR" config user.name "$current_name"
  fi
  if [[ -z "$current_email" ]]; then
    current_email="$(prompt_required "Git user.email")"
    git -C "$VAULT_DIR" config user.email "$current_email"
  fi
}

setup_git() {
  if ! prompt_yes_no "Set up Git for this vault?" "y"; then return; fi

  if ! git -C "$VAULT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$VAULT_DIR" init -b main
  fi

  configure_git_identity
  git -C "$VAULT_DIR" add .
  if ! git -C "$VAULT_DIR" diff --cached --quiet; then
    git -C "$VAULT_DIR" commit -m "Initial vault setup"
  fi

  if ! prompt_yes_no "Connect this vault to a GitHub repository?" "y"; then return; fi

  if ! command_exists gh; then
    echo "GitHub CLI not found. Install from https://cli.github.com"
    return
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run 'gh auth login' then re-run setup."
    return
  fi

  echo
  echo "Action options: create (new repo), existing (connect existing), skip"
  local action
  action="$(prompt_default "Action" "create")"

  case "$action" in
    create)
      local repo_name visibility
      repo_name="$(prompt_default "New repo name" "$(basename "$VAULT_DIR")")"
      visibility="$(prompt_default "Visibility (private/public)" "private")"
      [[ "$visibility" != "public" ]] && visibility="private"
      gh repo create "$repo_name" "--$visibility" --source "$VAULT_DIR" --remote origin --push
      ;;
    existing)
      local repo_full
      repo_full="$(prompt_required "Existing repo (owner/name)")"
      git -C "$VAULT_DIR" remote add origin "https://github.com/$repo_full.git"
      if prompt_yes_no "Push now?" "y"; then
        git -C "$VAULT_DIR" push -u origin HEAD
      fi
      ;;
    *)
      echo "Skipping GitHub."
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────
# BEGIN SETUP
# ─────────────────────────────────────────────────────────────

clear
printf "┌──────────────────────────────────────────┐\n"
printf "│           Agent Vault Setup              │\n"
printf "└──────────────────────────────────────────┘\n"
echo

# ── Step 1: Name ──────────────────────────

DEFAULT_USER_NAME="$(id -F 2>/dev/null || whoami)"
USER_NAME="$(prompt_default "What should the system call you?" "$DEFAULT_USER_NAME")"

# ── Step 2: Vault location ────────────────

section "Vault Location"
cat <<'MSG'
The vault is a folder on your computer where your agents work.
Projects, notes, logs, and tool configurations all live here.
MSG
echo
DEFAULT_VAULT_DIR="$HOME/Documents/agent-vault"
VAULT_DIR="$(prompt_default "Where should the vault be created?" "$DEFAULT_VAULT_DIR")"
VAULT_DIR="${VAULT_DIR/#\~/$HOME}"

if [[ -d "$VAULT_DIR" ]]; then
  echo
  echo "That folder already exists."
  if ! prompt_yes_no "Continue and set up inside it?" "y"; then
    echo "Choose a different path and re-run setup."
    exit 1
  fi
fi

# ── Step 3: Platform selection ────────────

section "Agent Platforms"
cat <<'MSG'
Choose which AI platforms you want your agents deployed to.
Arrow keys to move, space to select, enter to confirm.
MSG
echo

PLATFORM_OPTIONS=("Claude Code" "OpenClaw" "Codex" "ChatGPT")
SELECTED_PLATFORMS=()
multiselect SELECTED_PLATFORMS "${PLATFORM_OPTIONS[@]}"

if [[ ${#SELECTED_PLATFORMS[@]} -eq 0 ]]; then
  echo "No platforms selected — defaulting to Claude Code."
  SELECTED_PLATFORMS=("Claude Code")
fi
echo "Selected: ${SELECTED_PLATFORMS[*]}"

# ── Step 4: Agents ────────────────────────

section "Your Agents"
cat <<'MSG'
Let's create your first agents. Each one handles a specific,
repeatable type of task — one job, done consistently.

Think of something like: "every time we finish a sprint, I need
to pull together a stakeholder update from Jira and summarize
what shipped, what slipped, and why" — that's a great candidate
for an agent.
MSG
echo

AGENT_NAMES=()
AGENT_SLUGS=()
AGENT_SUMMARIES=()

while true; do
  agent_num=$((${#AGENT_NAMES[@]} + 1))
  echo "── Agent $agent_num"
  agent_name="$(prompt_required "Agent name (e.g. 'Post-call summary', 'Weekly pipeline review')")"
  agent_summary="$(prompt_required "What does this agent help you with?")"
  AGENT_NAMES+=("$agent_name")
  AGENT_SLUGS+=("$(slugify "$agent_name")")
  AGENT_SUMMARIES+=("$agent_summary")
  echo
  if [[ ${#AGENT_NAMES[@]} -ge 1 ]]; then
    if ! prompt_yes_no "Add another agent?" "n"; then
      break
    fi
    echo
  fi
done

# ── Step 5: Tool selection ────────────────

section "Connected Tools"
cat <<'MSG'
Select the tools your agents should be able to access.
Arrow keys to move, space to select, enter to confirm.
MSG
echo

TOOL_OPTIONS=(
  "Atlassian (Jira + Confluence)"
  "Notion"
  "Salesforce"
  "Slack"
  "GitHub"
)
SELECTED_TOOLS=()
multiselect SELECTED_TOOLS "${TOOL_OPTIONS[@]}"
echo "Selected: ${SELECTED_TOOLS[*]:-none}"

# ── Step 6: Tool setup wizards ────────────

if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
  section "Tool Setup"
  echo "Walking through each tool now."
  echo

  for tool in "${SELECTED_TOOLS[@]}"; do
    echo "── $tool"
    echo
    case "$tool" in
      "Atlassian (Jira + Confluence)") setup_atlassian ;;
      "Notion")                        setup_notion ;;
      "Salesforce")                    setup_salesforce ;;
      "Slack")                         setup_slack ;;
      "GitHub")                        setup_github ;;
    esac
    echo
  done
fi

# ── Step 7: Create vault structure ────────

section "Creating Vault"
echo "Building vault at: $VAULT_DIR"
echo

VAULT_DIRS=(
  "00 Inbox"
  "01 Projects"
  "02 Areas"
  "03 Resources"
  "04 Archive"
  "90 Ops/Agents/Claude Code"
  "90 Ops/Agents/OpenClaw"
  "90 Ops/Agents/Codex"
  "90 Ops/Agents/ChatGPT"
  "91 Templates"
  "92 Dashboards"
  "93 Attachments"
  ".claude/agents"
)
for d in "${VAULT_DIRS[@]}"; do
  ensure_dir "$VAULT_DIR/$d"
done

# Copy static files from the installer package
# Copy AGENTS.md as CLAUDE.md (Claude Code reads CLAUDE.md as its project instructions)
[[ -f "$SCRIPT_DIR/AGENTS.md" ]] && cp "$SCRIPT_DIR/AGENTS.md" "$VAULT_DIR/CLAUDE.md"
for f in HEARTBEAT.md "Vault Home.md"; do
  [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$VAULT_DIR/$f"
done

# Copy templates so users can reference and modify them
[[ -d "$TEMPLATES_DIR" ]] && cp -r "$TEMPLATES_DIR" "$VAULT_DIR/"

# Write .gitignore
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

# ── Step 8: Write .mcp.json ───────────────

write_mcp_json
if [[ ${#MCP_ENTRIES[@]} -gt 0 ]]; then
  echo ".mcp.json written (gitignored — contains your credentials)"
fi

# ── Step 9: Generate vault documents ──────

TUTORIAL_DIR="$VAULT_DIR/01 Projects/Agent Setup Tutorial"
ensure_dir "$TUTORIAL_DIR"

PLATFORM_LIST=""
for p in "${SELECTED_PLATFORMS[@]}"; do PLATFORM_LIST+="- $p"$'\n'; done

TOOL_LIST=""
if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
  for t in "${SELECTED_TOOLS[@]}"; do TOOL_LIST+="- $t"$'\n'; done
else
  TOOL_LIST="None configured yet."
fi

cat > "$VAULT_DIR/90 Ops/First Run.md" <<EOF
# First Run

## What This Is

This vault is the shared working space for $USER_NAME and their agents.

It holds active projects, reference material, agent configurations,
and the connections to the tools your workflows depend on.

## Agent Platforms

$PLATFORM_LIST
## Agents

$(for i in "${!AGENT_NAMES[@]}"; do printf '%d. **%s** — %s\n' "$((i+1))" "${AGENT_NAMES[$i]}" "${AGENT_SUMMARIES[$i]}"; done)

## Connected Tools

$TOOL_LIST
## Next Step

Open \`01 Projects/Agent Setup Tutorial/project.md\` and follow the tasks there.
EOF

cat > "$TUTORIAL_DIR/project.md" <<EOF
---
type: project
status: active
owner: $USER_NAME
---

# Agent Setup Tutorial

## Goal

Get the vault working end-to-end for $USER_NAME.

## Platforms

$PLATFORM_LIST
## Agents

$(for i in "${!AGENT_NAMES[@]}"; do printf -- '- **%s**: %s\n' "${AGENT_NAMES[$i]}" "${AGENT_SUMMARIES[$i]}"; done)

## Done when

- At least one workflow agent is tested and working
- At least one tool connection is verified
- The vault is committed to Git
- The next real project has been started
EOF

cat > "$TUTORIAL_DIR/tasks.md" <<EOF
# Tasks

## Orientation

EOF
append_task "$TUTORIAL_DIR/tasks.md" "Read \`90 Ops/First Run.md\`."
append_task "$TUTORIAL_DIR/tasks.md" "Open Claude Code with this folder as the project root."
append_task "$TUTORIAL_DIR/tasks.md" "Ask your agent to describe what it can see in the vault."

if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
  printf '\n## Verify tool connections\n\n' >> "$TUTORIAL_DIR/tasks.md"
  for tool in "${SELECTED_TOOLS[@]}"; do
    append_task "$TUTORIAL_DIR/tasks.md" "Test the $tool connection: ask your agent to fetch something from it."
  done
fi

printf '\n## First workflow\n\n' >> "$TUTORIAL_DIR/tasks.md"
append_task "$TUTORIAL_DIR/tasks.md" "Run a real task through the '${AGENT_NAMES[0]}' agent."
append_task "$TUTORIAL_DIR/tasks.md" "Note anything the agent needed but didn't have."
append_task "$TUTORIAL_DIR/tasks.md" "Create the next real project in \`01 Projects/\`."

cat > "$TUTORIAL_DIR/log.md" <<EOF
# Log

- $(date +%Y-%m-%d): Vault initialized for $USER_NAME.
  Platforms: ${SELECTED_PLATFORMS[*]}
  Tools: ${SELECTED_TOOLS[*]:-none}
EOF

cat > "$TUTORIAL_DIR/decisions.md" <<EOF
# Decisions

- Vault created at: $VAULT_DIR
- Platforms: ${SELECTED_PLATFORMS[*]}
- Tools: ${SELECTED_TOOLS[*]:-none}
- Agents defined: $(IFS=', '; echo "${AGENT_NAMES[*]}")
EOF

# ── Step 10: Generate agent files ─────────

for platform in "${SELECTED_PLATFORMS[@]}"; do
  for i in "${!AGENT_NAMES[@]}"; do
    agent_name="${AGENT_NAMES[$i]}"
    agent_slug="${AGENT_SLUGS[$i]}"
    case "$platform" in
      "Claude Code")
        if [[ -f "$TEMPLATES_DIR/claude-code/subagent.md.template" ]]; then
          write_from_template \
            "$TEMPLATES_DIR/claude-code/subagent.md.template" \
            "$VAULT_DIR/90 Ops/Agents/Claude Code/$agent_slug.md" \
            "$agent_name" "$agent_slug"
          cp "$VAULT_DIR/90 Ops/Agents/Claude Code/$agent_slug.md" \
             "$VAULT_DIR/.claude/agents/$agent_slug.md"
        fi
        ;;
      "OpenClaw")
        if [[ -f "$TEMPLATES_DIR/openclaw/AGENTS.md.template" ]]; then
          write_from_template \
            "$TEMPLATES_DIR/openclaw/AGENTS.md.template" \
            "$VAULT_DIR/90 Ops/Agents/OpenClaw/$agent_slug/AGENTS.md" \
            "$agent_name" "$agent_slug"
          write_from_template \
            "$TEMPLATES_DIR/openclaw/BOOTSTRAP.md.template" \
            "$VAULT_DIR/90 Ops/Agents/OpenClaw/$agent_slug/BOOTSTRAP.md" \
            "$agent_name" "$agent_slug"
        fi
        ;;
      "Codex")
        if [[ -f "$TEMPLATES_DIR/codex-skill/SKILL.md.template" ]]; then
          write_from_template \
            "$TEMPLATES_DIR/codex-skill/SKILL.md.template" \
            "$VAULT_DIR/90 Ops/Agents/Codex/$agent_slug/SKILL.md" \
            "$agent_name" "$agent_slug"
        fi
        ;;
      "ChatGPT")
        if [[ -f "$TEMPLATES_DIR/chatgpt/custom-gpt.md.template" ]]; then
          write_from_template \
            "$TEMPLATES_DIR/chatgpt/custom-gpt.md.template" \
            "$VAULT_DIR/90 Ops/Agents/ChatGPT/$agent_slug.md" \
            "$agent_name" "$agent_slug"
        fi
        ;;
    esac
  done
done

# ── Step 11: Git / GitHub ─────────────────

section "Git Setup"
setup_git

# ── Done ──────────────────────────────────

section "Setup Complete"
printf "Your vault is ready at:\n  %s\n\n" "$VAULT_DIR"
echo "Start here:"
printf "  %s/90 Ops/First Run.md\n" "$VAULT_DIR"
printf "  %s/01 Projects/Agent Setup Tutorial/project.md\n" "$VAULT_DIR"
echo
echo "Open Claude Code with that folder as the project root to get started."
echo
