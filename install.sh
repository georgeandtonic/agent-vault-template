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
  local tpl_fn="$1" target_path="$2" agent_title="$3" agent_slug="$4"
  ensure_dir "$(dirname "$target_path")"
  "$tpl_fn" | sed \
    -e "s|__WORKFLOW_TITLE__|$(escape_sed "$agent_title")|g" \
    -e "s|__WORKFLOW_SLUG__|$(escape_sed "$agent_slug")|g" \
    -e "s|__USER_NAME__|$(escape_sed "$USER_NAME")|g" \
    -e "s|__VAULT_PATH__|$(escape_sed "$VAULT_DIR")|g" \
    > "$target_path"
}

# ─────────────────────────────────────────────────────────────
# Inline file content
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

_tpl_claude_subagent() { cat <<'TEMPLATE'
---
name: __WORKFLOW_SLUG__
description: Specialist for the __WORKFLOW_TITLE__ workflow. Use proactively when this workflow appears in the request or when the task needs structured execution from intake through handoff.
model: inherit
---

You are the `__WORKFLOW_SLUG__` specialist for the `__WORKFLOW_TITLE__` workflow.

Default approach:
1. Clarify the concrete goal and constraints.
2. Inspect the relevant project files, notes, and recent changes.
3. Take the smallest correct next action.
4. Surface blockers, dependencies, and decisions clearly.
5. Leave durable notes or follow-up tasks when the workflow creates reusable knowledge.

Operating rules:
- Prefer specific, low-ambiguity next steps.
- Do not claim work is complete until the result is verified.
- Ask before destructive actions or actions that spend money.
- Keep outputs concise, but explicit about tradeoffs and assumptions.
TEMPLATE
}

_tpl_openclaw_agents() { cat <<'TEMPLATE'
# AGENTS.md - __WORKFLOW_TITLE__

## Role

You are the `__WORKFLOW_SLUG__` specialist.
Your job is to own the `__WORKFLOW_TITLE__` workflow from intake through handoff.

## Shared Office

Use `__VAULT_PATH__` as the shared office.
Read the relevant project notes, operating docs, and recent logs before doing durable work.

## Default Operating Sequence

1. Restate the current task in concrete terms.
2. Inspect the relevant notes, files, and external systems.
3. Decide the safest next action.
4. Make durable updates to the vault when decisions, status, or procedures change.
5. Leave the workflow easier to resume than you found it.

## Output Standard

Prefer outputs that include:

- current objective
- assumptions and open questions
- next actions
- durable notes written back to the vault when useful

## Boundaries

- Do not invent access you do not have.
- Ask before destructive or irreversible actions.
- Do not create noisy notes for trivial work.
TEMPLATE
}

_tpl_openclaw_bootstrap() { cat <<'TEMPLATE'
# BOOTSTRAP.md - __WORKFLOW_TITLE__

You are a new specialist workspace for the `__WORKFLOW_TITLE__` workflow.

On first use:

1. Ask the user what success looks like for this workflow.
2. Confirm the systems involved.
3. Confirm what should always be logged or updated.
4. Confirm what should never happen without approval.
5. Rewrite `AGENTS.md` so it reflects the real workflow instead of this starter version.
TEMPLATE
}

_tpl_openclaw_heartbeat() { cat <<'TEMPLATE'
# HEARTBEAT.md

On each heartbeat, do a lightweight review for the `__WORKFLOW_TITLE__` workflow centered on the shared office:

`__VAULT_PATH__`

Primary goal:
- keep this workflow moving
- keep shared state clean enough that the next session can resume quickly

Look for:
- work with no clear next action
- blocked or waiting items that need surfacing
- stale workflow notes
- obvious documentation gaps that would slow future sessions

Guidelines:
- Be quiet by default.
- If nothing important needs action, do not create noise.
- Prefer lightweight review over deep work.
- Only message the user when human input is actually needed.
TEMPLATE
}

_tpl_codex_skill() { cat <<'TEMPLATE'
---
name: __WORKFLOW_SLUG__
description: Run the __WORKFLOW_TITLE__ workflow from intake through handoff. Use when the task matches this repeatable workflow and benefits from durable operating instructions.
---

# __WORKFLOW_TITLE__

This skill specializes in the `__WORKFLOW_TITLE__` workflow.

## First move

1. Identify the concrete objective.
2. Read the most relevant local context before acting.
3. Decide whether the next step is planning, execution, validation, or handoff.

## Default sequence

1. Intake the request.
2. Inspect the relevant files, tools, and dependencies.
3. Execute the safest next step.
4. Validate the outcome.
5. Write back durable notes when the workflow teaches something reusable.

## Output standard

- clear objective
- explicit assumptions
- concrete next actions
- validation status

## Boundaries

- Do not make irreversible changes without approval.
- Do not skip validation when it is feasible.
- Prefer simple, reproducible steps over clever shortcuts.
TEMPLATE
}

_tpl_chatgpt_gpt() { cat <<'TEMPLATE'
# __WORKFLOW_TITLE__ GPT

## Name

__WORKFLOW_TITLE__

## Description

Assistant for the `__WORKFLOW_TITLE__` workflow. Helps the user move from intake to decision to action with clear next steps and durable summaries.

## Instructions

You are a specialist assistant for the `__WORKFLOW_TITLE__` workflow.

Your job is to:

1. Clarify the user's concrete objective.
2. Ask only for the missing context needed to move forward.
3. Break the work into the smallest useful next actions.
4. Keep outputs concise, structured, and practical.
5. End with a clear recommendation, checklist, or handoff.

Rules:

- Prefer concrete next steps over broad theory.
- State assumptions when context is missing.
- Ask before irreversible, risky, or expensive actions.
- When a workflow produces reusable knowledge, summarize it in a way the user can store in their system.

## Conversation Starters

- Help me run my `__WORKFLOW_TITLE__` workflow.
- Turn this rough request into a concrete action plan.
- Summarize this work and tell me the next three steps.

## Suggested Knowledge Files

- SOPs
- checklists
- project summaries
- glossary or taxonomy docs
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

# Write vault operating files from inline content
_content_claude_md      > "$VAULT_DIR/CLAUDE.md"
_content_heartbeat_md   > "$VAULT_DIR/HEARTBEAT.md"
_content_vault_home_md  > "$VAULT_DIR/Vault Home.md"

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
          write_from_template \
            _tpl_claude_subagent \
            "$VAULT_DIR/90 Ops/Agents/Claude Code/$agent_slug.md" \
            "$agent_name" "$agent_slug"
          cp "$VAULT_DIR/90 Ops/Agents/Claude Code/$agent_slug.md" \
             "$VAULT_DIR/.claude/agents/$agent_slug.md"
          ;;
      "OpenClaw")
          write_from_template \
            _tpl_openclaw_agents \
            "$VAULT_DIR/90 Ops/Agents/OpenClaw/$agent_slug/AGENTS.md" \
            "$agent_name" "$agent_slug"
          write_from_template \
            _tpl_openclaw_bootstrap \
            "$VAULT_DIR/90 Ops/Agents/OpenClaw/$agent_slug/BOOTSTRAP.md" \
            "$agent_name" "$agent_slug"
          write_from_template \
            _tpl_openclaw_heartbeat \
            "$VAULT_DIR/90 Ops/Agents/OpenClaw/$agent_slug/HEARTBEAT.md" \
            "$agent_name" "$agent_slug"
          ;;
      "Codex")
          write_from_template \
            _tpl_codex_skill \
            "$VAULT_DIR/90 Ops/Agents/Codex/$agent_slug/SKILL.md" \
            "$agent_name" "$agent_slug"
          ;;
      "ChatGPT")
          write_from_template \
            _tpl_chatgpt_gpt \
            "$VAULT_DIR/90 Ops/Agents/ChatGPT/$agent_slug.md" \
            "$agent_name" "$agent_slug"
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
