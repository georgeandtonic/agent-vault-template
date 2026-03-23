#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
      local seq1 seq2
      IFS= read -rsn1 seq1; IFS= read -rsn1 seq2
      seq="$seq1$seq2"
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

trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'; }

ensure_dir() { mkdir -p "$1"; }

escape_sed() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

append_task() {
  printf -- "- [ ] %s\n" "$2" >> "$1"
}

# ─────────────────────────────────────────────────────────────
# Inline vault file content
# ─────────────────────────────────────────────────────────────

_content_claude_md() { cat <<'TEMPLATE'
# Agent Vault Operating Rules

## Purpose

This vault is the shared working office for the user and their agents.
Treat it as the source of truth for project state, task state, decisions, logs, and reusable knowledge.

## Core Rules

- Prefer updating existing project notes over creating duplicate notes.
- Keep folders shallow and use note properties or note content for structure.
- New unclassified material goes into `00 Inbox/`.
- Active work lives in `01 Projects/`.
- Ongoing responsibilities live in `02 Areas/`.
- Reusable reference material lives in `03 Resources/`.
- Finished or inactive material moves to `04 Archive/`.
- Shared operating docs live in `90 Ops/`.
- Templates live in `91 Templates/`.
- Dashboard and index notes live in `92 Dashboards/`.
- Attachments and exported media live in `93 Attachments/`.

## Project Standard

Each active project should usually have one folder under `01 Projects/` with this structure:

- `project.md`
- `tasks.md`
- `log.md`
- `decisions.md`
- `meetings/`
- `artifacts/`

Do not invent a new structure unless the project clearly needs it.

## Work Pattern

When working on a project:

1. Update `project.md` for scope, status, current focus, and key links.
2. Update `tasks.md` for actionable next steps.
3. Append to `log.md` for meaningful progress.
4. Record durable decisions in `decisions.md`.
5. Put meeting notes in `meetings/`.

## Note Hygiene

- Prefer one canonical note per thing.
- Avoid creating multiple competing task lists for the same project.
- Use links between notes instead of duplicating text.
- Keep logs append-only unless cleanup is clearly safe.
- Archive stale or completed work instead of deleting it.

## Properties

Use these properties where relevant:

- `type`
- `status`
- `owner`
- `project`
- `area`
- `next_review`
- `created`
- `updated`
- `tags`

## Default Behavior

- If unsure where something goes, put it in `00 Inbox/`.
- If creating a new project, start from the project template or the standard project structure.
- If cleaning up, reduce duplication and improve clarity without changing meaning.

## Recurring Review

- Recurring review and away-from-user check-in behavior lives in `HEARTBEAT.md`.
- Keep recurring review lightweight and quiet by default.
- Use recurring review to keep active work moving and project state resumable.
- Do not use recurring review for noisy churn or major unsupervised work.
TEMPLATE
}

_content_heartbeat_md() { cat <<'TEMPLATE'
# HEARTBEAT.md

Use this file to define how the system should do lightweight recurring review when the user is away.

The exact mechanism depends on the runtime:

- OpenClaw can use a native heartbeat mechanism.
- Other runtimes can use this file as the source-of-truth policy for scheduled or manual recurring review.

## Default Intent

On each recurring check-in:

- review active projects
- look for missing next actions
- notice blockers or stale work
- keep the vault easy to resume

## Guidelines

- Be quiet by default.
- Prefer lightweight review over deep work.
- Only interrupt the user when there is a blocker, decision, approval boundary, or time-sensitive issue.
- Avoid noisy maintenance and repetitive edits.
- Update durable notes only when it materially improves future work.
TEMPLATE
}

_content_vault_home_md() { cat <<'TEMPLATE'
# Vault Home

Use this page as the main entry point for the vault.

## Start Here

- [[90 Ops/First Run]]
- [[01 Projects/Agent Setup Tutorial/project]]
- [[01 Projects/Agent Setup Tutorial/tasks]]

## Core Areas

- [[00 Inbox]]
- [[01 Projects]]
- [[02 Areas]]
- [[03 Resources]]
- [[04 Archive]]
- [[90 Ops]]
- [[91 Templates]]
- [[92 Dashboards]]
TEMPLATE
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


setup_github() {
  echo "GitHub connects using the GitHub CLI (gh)."
  echo

  if ! command_exists gh; then
    echo "The GitHub CLI is not installed."
    echo "Install it from https://cli.github.com then re-run setup."
    echo
    if prompt_yes_no "Skip GitHub for now?" "y"; then
      return
    fi
    return
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "You're not logged in to GitHub. Opening browser login now..."
    echo
    gh auth login
  fi

  local token
  token="$(gh auth token 2>/dev/null || true)"
  if [[ -z "$token" ]]; then
    echo "Could not retrieve GitHub token. Skipping."
    return
  fi

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
cat <<'MSG'
Agent Vault is a structured workspace that lives on your computer
and gives your AI agent a shared office to work from.

Instead of starting every conversation from scratch, your agent
will have access to your active projects, running task lists,
decision history, and connected tools — all in one place.

Everything is organized into a simple folder structure:

  01 Projects/   — active work, one folder per project
  02 Areas/      — ongoing responsibilities
  03 Resources/  — reference material
  04 Archive/    — completed or inactive work
  90 Ops/        — vault-level operating docs

This setup will ask you a few questions, connect any tools
you use, and create the vault folder on your machine.

MSG
read -r -p "Press enter to get started..."
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

# ── Step 3: Tool selection ────────────────

section "Connected Tools"
cat <<'MSG'
Select the tools your agents should be able to access.
Arrow keys to move, space to select, enter to confirm.
MSG
echo

TOOL_OPTIONS=(
  "Atlassian (Jira + Confluence)"
  "GitHub"
)
SELECTED_TOOLS=()
multiselect SELECTED_TOOLS "${TOOL_OPTIONS[@]}"
echo "Selected: ${SELECTED_TOOLS[*]:-none}"

# ── Step 4: Tool setup wizards ────────────

if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
  section "Tool Setup"
  echo "Walking through each tool now."
  echo

  for tool in "${SELECTED_TOOLS[@]}"; do
    echo "── $tool"
    echo
    case "$tool" in
      "Atlassian (Jira + Confluence)") setup_atlassian ;;
      "GitHub")                        setup_github ;;
    esac
    echo
  done
fi

# ── Step 5: Create vault structure ────────

section "Creating Vault"
echo "Building vault at: $VAULT_DIR"
echo

VAULT_DIRS=(
  "00 Inbox"
  "01 Projects"
  "02 Areas"
  "03 Resources"
  "04 Archive"
  "90 Ops"
  "91 Templates"
  "92 Dashboards"
  "93 Attachments"
)
for d in "${VAULT_DIRS[@]}"; do
  ensure_dir "$VAULT_DIR/$d"
done

_content_claude_md      > "$VAULT_DIR/CLAUDE.md"
_content_heartbeat_md   > "$VAULT_DIR/HEARTBEAT.md"
_content_vault_home_md  > "$VAULT_DIR/Vault Home.md"

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

# ── Step 6: Write .mcp.json ───────────────

write_mcp_json
if [[ ${#MCP_ENTRIES[@]} -gt 0 ]]; then
  echo ".mcp.json written (gitignored — contains your credentials)"
fi

# ── Step 7: Generate vault documents ──────

TUTORIAL_DIR="$VAULT_DIR/01 Projects/Agent Setup Tutorial"
ensure_dir "$TUTORIAL_DIR"

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

It holds active projects, reference material, and the connections
to the tools your workflows depend on.

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

## Done when

- At least one tool connection is verified
- The vault is committed to Git
- The first real project has been started
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

printf '\n## Get started\n\n' >> "$TUTORIAL_DIR/tasks.md"
append_task "$TUTORIAL_DIR/tasks.md" "Create the first real project in \`01 Projects/\`."
append_task "$TUTORIAL_DIR/tasks.md" "Run a real task with your agent and note what it needed but didn't have."

cat > "$TUTORIAL_DIR/log.md" <<EOF
# Log

- $(date +%Y-%m-%d): Vault initialized for $USER_NAME.
  Tools: ${SELECTED_TOOLS[*]:-none}
EOF

cat > "$TUTORIAL_DIR/decisions.md" <<EOF
# Decisions

- Vault created at: $VAULT_DIR
- Tools: ${SELECTED_TOOLS[*]:-none}
EOF

# ── Step 8: Git / GitHub ─────────────────

section "Git Setup"
setup_git

# ── Done ──────────────────────────────────

section "Setup Complete"
printf "Your vault is ready at:\n  %s\n\n" "$VAULT_DIR"
cat <<MSG
How to use it:

  1. Open a terminal and navigate to your vault:
       cd "$VAULT_DIR"

  2. Start a Claude Code session there:
       claude

     Claude will read the vault structure automatically and know
     how to organize your work — projects, tasks, decisions,
     and logs will all stay in the right place.

  3. You can also open the folder in VS Code to browse files:
       code "$VAULT_DIR"

     This is useful for reading project notes, reviewing what
     your agent has written, or editing things directly.

A good first message to your agent:
  "Read First Run.md in 90 Ops and walk me through the vault."

MSG
