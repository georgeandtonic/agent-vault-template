#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$ROOT_DIR/templates"

prompt_default() {
  local label="$1"
  local default_value="$2"
  local value
  read -r -p "$label [$default_value]: " value
  if [[ -z "$value" ]]; then
    value="$default_value"
  fi
  printf '%s' "$value"
}

prompt_required() {
  local label="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$label: " value
  done
  printf '%s' "$value"
}

prompt_yes_no() {
  local label="$1"
  local default_value="$2"
  local value
  read -r -p "$label [$default_value]: " value
  value="${value:-$default_value}"
  case "$value" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_choice() {
  local label="$1"
  local default_value="$2"
  local value
  read -r -p "$label [$default_value]: " value
  printf '%s' "${value:-$default_value}"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/-\{2,\}/-/g' \
    | sed 's/^-//' \
    | sed 's/-$//'
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

ensure_dir() {
  mkdir -p "$1"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

github_cli_authenticated() {
  gh auth status >/dev/null 2>&1
}

github_repo_picker() {
  local repo_lines
  local repo_names=()
  local line
  local index=1
  local choice

  repo_lines="$(gh repo list --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)"
  if [[ -z "$repo_lines" ]]; then
    printf ''
    return
  fi

  echo "Select an existing GitHub repo:"
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      repo_names+=("$line")
      printf '%s. %s\n' "$index" "$line"
      index=$((index + 1))
    fi
  done <<< "$repo_lines"

  if [[ ${#repo_names[@]} -eq 0 ]]; then
    printf ''
    return
  fi

  read -r -p "Existing repo number or owner/repo: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#repo_names[@]} )); then
    printf '%s' "${repo_names[$((choice - 1))]}"
  else
    printf '%s' "$choice"
  fi
}

workflow_number_for_name() {
  local input
  input="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$input" in
    1|workflow1|workflow-1|first|"${WORKFLOW_1_SLUG}") printf '1' ;;
    2|workflow2|workflow-2|second|"${WORKFLOW_2_SLUG}") printf '2' ;;
    both|all|1,2|2,1) printf 'both' ;;
    *) printf '' ;;
  esac
}

service_supports_workflow() {
  local mapping="$1"
  local workflow_number="$2"
  case "$mapping" in
    both|all|1,2|2,1) return 0 ;;
    "$workflow_number") return 0 ;;
    *) return 1 ;;
  esac
}

write_file_from_template() {
  local template_path="$1"
  local target_path="$2"
  local workflow_title="$3"
  local workflow_slug="$4"
  local vault_path="$5"
  local escaped_title
  local escaped_slug
  local escaped_vault_path
  escaped_title="$(escape_sed_replacement "$workflow_title")"
  escaped_slug="$(escape_sed_replacement "$workflow_slug")"
  escaped_vault_path="$(escape_sed_replacement "$vault_path")"
  ensure_dir "$(dirname "$target_path")"
  sed \
    -e "s|__WORKFLOW_TITLE__|$escaped_title|g" \
    -e "s|__WORKFLOW_SLUG__|$escaped_slug|g" \
    -e "s|__VAULT_PATH__|$escaped_vault_path|g" \
    "$template_path" > "$target_path"
}

append_task() {
  local file_path="$1"
  local task_text="$2"
  printf -- "- [ ] %s\n" "$task_text" >> "$file_path"
}

append_workflow_context() {
  local file_path="$1"
  local workflow_title="$2"
  local workflow_summary="$3"
  local workflow_number="$4"
  local service_count="$5"
  local i=0

  {
    printf '\n## Workflow Context\n\n'
    printf 'Summary: %s\n' "$workflow_summary"
    printf '\nConnected services:\n'
  } >> "$file_path"

  if [[ "$service_count" -eq 0 ]]; then
    printf -- '- none selected yet\n' >> "$file_path"
    return
  fi

  while [[ $i -lt $service_count ]]; do
    local service_name="${SERVICE_NAMES[$i]}"
    local service_use="${SERVICE_USES[$i]}"
    local service_mapping="${SERVICE_WORKFLOW_MAPS[$i]}"
    if service_supports_workflow "$service_mapping" "$workflow_number"; then
      printf -- '- %s: %s\n' "$service_name" "$service_use" >> "$file_path"
    fi
    i=$((i + 1))
  done
}

write_repo_heartbeat() {
  cat > "$VAULT_DIR/HEARTBEAT.md" <<EOF
# HEARTBEAT.md

This file defines the recurring review policy for this vault.

Cadence:
- $HEARTBEAT_CADENCE

Quiet mode:
- $HEARTBEAT_QUIET

$(if [[ "$HEARTBEAT_ENABLED" == "yes" ]]; then printf '%s\n' "Recurring review is enabled."; else printf '%s\n' "Recurring review is currently disabled. Keep this file as the policy reference and enable it later when ready."; fi)

On each recurring check-in:

- review active projects in \`01 Projects/\`
- check \`00 Inbox/\` for items that should move into projects or areas
- inspect \`90 Ops/Work Queue.md\` when it exists
- look for stale status, unclear next actions, blockers, and missing handoffs

Guidelines:

- Be quiet by default.
- Prefer lightweight review over deep work.
- Only interrupt the user when input is actually needed.
- Avoid noisy maintenance and repetitive edits.
- Update durable notes only when it materially improves future work.
EOF
}

write_heartbeat_config() {
  cat > "$VAULT_DIR/90 Ops/Heartbeat Config.md" <<EOF
# Heartbeat Config

## Purpose

Define how recurring review should work when the user is away.

## Status

- enabled: $HEARTBEAT_ENABLED
- cadence: $HEARTBEAT_CADENCE
- quiet mode: $HEARTBEAT_QUIET

## Review Targets

- \`00 Inbox/\`
- \`01 Projects/\`
- \`90 Ops/Work Queue.md\` when present
- recent logs and decisions only when needed

## Review Goals

- keep active work moving
- surface blockers or stale work
- keep project state resumable
- avoid noisy churn
EOF
}

write_openclaw_heartbeat() {
  local target_path="$1"
  local workflow_title="$2"
  local workflow_slug="$3"
  local escaped_title
  local escaped_slug
  local escaped_vault_path
  local escaped_cadence
  escaped_title="$(escape_sed_replacement "$workflow_title")"
  escaped_slug="$(escape_sed_replacement "$workflow_slug")"
  escaped_vault_path="$(escape_sed_replacement "$VAULT_DIR")"
  escaped_cadence="$(escape_sed_replacement "$HEARTBEAT_CADENCE")"
  ensure_dir "$(dirname "$target_path")"
  sed \
    -e "s|__WORKFLOW_TITLE__|$escaped_title|g" \
    -e "s|__WORKFLOW_SLUG__|$escaped_slug|g" \
    -e "s|__VAULT_PATH__|$escaped_vault_path|g" \
    -e "s|__HEARTBEAT_CADENCE__|$escaped_cadence|g" \
    "$TEMPLATES_DIR/openclaw/HEARTBEAT.md.template" > "$target_path"
}

configure_git_identity_if_needed() {
  local current_name
  local current_email
  current_name="$(git -C "$VAULT_DIR" config user.name || true)"
  current_email="$(git -C "$VAULT_DIR" config user.email || true)"

  if [[ -z "$current_name" ]]; then
    current_name="$(prompt_default "Git user.name" "$USER_NAME")"
    git -C "$VAULT_DIR" config user.name "$current_name"
  fi

  if [[ -z "$current_email" ]]; then
    current_email="$(prompt_required "Git user.email")"
    git -C "$VAULT_DIR" config user.email "$current_email"
  fi
}

commit_setup_changes() {
  git -C "$VAULT_DIR" add .
  if git -C "$VAULT_DIR" diff --cached --quiet; then
    echo "No new setup changes to commit."
    return
  fi
  configure_git_identity_if_needed
  git -C "$VAULT_DIR" commit -m "Complete initial vault setup"
}

setup_github_remote() {
  local current_origin=""
  local git_action=""

  if ! prompt_yes_no "Set up Git and GitHub for this vault now?" "y"; then
    return
  fi

  if ! git -C "$VAULT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$VAULT_DIR" init -b main
  fi

  commit_setup_changes

  current_origin="$(git -C "$VAULT_DIR" remote get-url origin 2>/dev/null || true)"

  echo
  if [[ -n "$current_origin" ]]; then
    echo "Current origin: $current_origin"
    echo "GitHub action options: push, create, existing, skip"
    git_action="$(prompt_choice "GitHub action" "push")"
  else
    echo "GitHub action options: create, existing, skip"
    git_action="$(prompt_choice "GitHub action" "create")"
  fi

  case "$git_action" in
    push)
      if [[ -z "$current_origin" ]]; then
        echo "No origin exists yet. Choose create or existing instead."
        return
      fi
      git -C "$VAULT_DIR" push -u origin HEAD
      ;;
    create)
      if ! command_exists gh; then
        echo "GitHub CLI not found. Install gh or connect a remote later."
        return
      fi
      if ! github_cli_authenticated; then
        echo "GitHub CLI is not authenticated. Run 'gh auth login' and rerun setup if you want automated repo creation."
        return
      fi
      local repo_name
      local visibility
      repo_name="$(prompt_default "New GitHub repo name" "$(basename "$VAULT_DIR")")"
      visibility="$(prompt_choice "Repo visibility (private/public)" "private")"
      if [[ "$visibility" != "public" ]]; then
        visibility="private"
      fi
      if [[ -n "$current_origin" ]]; then
        git -C "$VAULT_DIR" remote remove origin
      fi
      gh repo create "$repo_name" "--$visibility" --source "$VAULT_DIR" --remote origin --push
      ;;
    existing)
      local repo_full_name
      local remote_url
      if command_exists gh && github_cli_authenticated; then
        repo_full_name="$(github_repo_picker)"
      else
        repo_full_name=""
      fi
      if [[ -z "$repo_full_name" ]]; then
        repo_full_name="$(prompt_required "Existing GitHub repo (owner/repo)")"
      fi
      remote_url="https://github.com/$repo_full_name.git"
      if [[ -n "$current_origin" ]]; then
        git -C "$VAULT_DIR" remote set-url origin "$remote_url"
      else
        git -C "$VAULT_DIR" remote add origin "$remote_url"
      fi
      if prompt_yes_no "Push current branch to $repo_full_name now?" "y"; then
        git -C "$VAULT_DIR" push -u origin HEAD
      fi
      ;;
    skip)
      ;;
    *)
      echo "Unknown GitHub action: $git_action"
      ;;
  esac
}

echo
echo "Agent Vault guided setup"
echo
echo "This setup will help you:"
echo "- understand what the vault is for"
echo "- choose the right agent runtime(s)"
echo "- define two real workflows"
echo "- map the external systems those workflows rely on"
echo "- scaffold platform-specific agent definitions"
echo "- initialize Git and optionally connect GitHub"
echo

DEFAULT_USER_NAME="$(id -F 2>/dev/null || whoami)"
USER_NAME="$(prompt_default "What should the system call you?" "$DEFAULT_USER_NAME")"

echo
echo "Pick the platforms you want to support."
echo "Use comma-separated values: openclaw, claude, codex, chatgpt"
PLATFORM_INPUT="$(prompt_default "Platforms" "claude,codex")"

IFS=',' read -r -a RAW_PLATFORMS <<< "$PLATFORM_INPUT"
PLATFORMS=()
for item in "${RAW_PLATFORMS[@]}"; do
  platform="$(trim "$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')")"
  if [[ -n "$platform" ]]; then
    PLATFORMS+=("$platform")
  fi
done

if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
  echo "No platforms selected. Exiting."
  exit 1
fi

echo
echo "This repository is currently at:"
echo "$ROOT_DIR"
echo
if [[ "$ROOT_DIR" != "$HOME/Documents/"* ]]; then
  echo "Recommended: keep your active vault under $HOME/Documents."
  echo "This installer will continue in place, but you may want to move the repo later."
fi

WORKFLOW_1_TITLE="$(prompt_required "Workflow 1 title")"
WORKFLOW_1_SUMMARY="$(prompt_required "Workflow 1 summary")"
WORKFLOW_2_TITLE="$(prompt_required "Workflow 2 title")"
WORKFLOW_2_SUMMARY="$(prompt_required "Workflow 2 summary")"
WORKFLOW_1_SLUG="$(slugify "$WORKFLOW_1_TITLE")"
WORKFLOW_2_SLUG="$(slugify "$WORKFLOW_2_TITLE")"

echo
echo "Select the services the user relies on."
echo "Use comma-separated values. Default: Atlassian,Salesforce,Dovetail,Slack"
SERVICE_INPUT="$(prompt_default "Services" "Atlassian,Salesforce,Dovetail,Slack")"
IFS=',' read -r -a RAW_SERVICES <<< "$SERVICE_INPUT"
SERVICE_NAMES=()
SERVICE_SLUGS=()
SERVICE_USES=()
SERVICE_WORKFLOW_MAPS=()
for item in "${RAW_SERVICES[@]}"; do
  service_name="$(trim "$item")"
  if [[ -z "$service_name" ]]; then
    continue
  fi
  SERVICE_NAMES+=("$service_name")
  SERVICE_SLUGS+=("$(slugify "$service_name")")
done

SERVICE_COUNT=${#SERVICE_NAMES[@]}
if [[ "$SERVICE_COUNT" -gt 0 ]]; then
  echo
  echo "Map each service to the workflows it supports."
fi

i=0
while [[ $i -lt $SERVICE_COUNT ]]; do
  service_name="${SERVICE_NAMES[$i]}"
  service_use="$(prompt_required "What do you do in $service_name?")"
  echo "Choose the workflow mapping for $service_name: 1, 2, or both"
  service_mapping="$(prompt_choice "Workflow mapping for $service_name" "both")"
  service_mapping="$(workflow_number_for_name "$service_mapping")"
  if [[ -z "$service_mapping" ]]; then
    service_mapping="both"
  fi
  SERVICE_USES+=("$service_use")
  SERVICE_WORKFLOW_MAPS+=("$service_mapping")
  i=$((i + 1))
done

if prompt_yes_no "Enable recurring review / heartbeat guidance?" "y"; then
  HEARTBEAT_ENABLED="yes"
  HEARTBEAT_CADENCE="$(prompt_default "Recurring review cadence" "weekday-daily")"
  if prompt_yes_no "Keep recurring review quiet unless action is needed?" "y"; then
    HEARTBEAT_QUIET="yes"
  else
    HEARTBEAT_QUIET="no"
  fi
else
  HEARTBEAT_ENABLED="no"
  HEARTBEAT_CADENCE="manual"
  HEARTBEAT_QUIET="yes"
fi

VAULT_DIR="$ROOT_DIR"
AGENT_SOURCE_DIR="$VAULT_DIR/90 Ops/Agents"
TUTORIAL_DIR="$VAULT_DIR/01 Projects/Agent Setup Tutorial"

ensure_dir "$AGENT_SOURCE_DIR/OpenClaw"
ensure_dir "$AGENT_SOURCE_DIR/Claude Code"
ensure_dir "$AGENT_SOURCE_DIR/Codex Skills"
ensure_dir "$AGENT_SOURCE_DIR/ChatGPT GPTs"
ensure_dir "$TUTORIAL_DIR"

write_repo_heartbeat
write_heartbeat_config

cat > "$VAULT_DIR/90 Ops/First Run.md" <<EOF
# First Run

## What This Is

This vault is the working home for $USER_NAME and their AI workflows.

It combines:

- durable notes
- project context
- reusable workflow agents
- setup and operating guidance

## How To Think About It

Build agents around repeatable workflows, not vague personas.

Good workflow agents know:

1. what triggers them
2. what context they should inspect first
3. which external systems they touch
4. what must be written down when the work is complete

## Platforms Chosen

$(printf -- '- %s\n' "${PLATFORMS[@]}")

## Initial Workflows

1. $WORKFLOW_1_TITLE
   Summary: $WORKFLOW_1_SUMMARY
2. $WORKFLOW_2_TITLE
   Summary: $WORKFLOW_2_SUMMARY

## Service Layer

$(i=0; while [[ $i -lt $SERVICE_COUNT ]]; do printf -- '- %s: %s (workflow %s)\n' "${SERVICE_NAMES[$i]}" "${SERVICE_USES[$i]}" "${SERVICE_WORKFLOW_MAPS[$i]}"; i=$((i + 1)); done)

## Recurring Review

- enabled: $HEARTBEAT_ENABLED
- cadence: $HEARTBEAT_CADENCE
- quiet mode: $HEARTBEAT_QUIET

## Git And GitHub

The installer can initialize Git, create the first commit, and optionally create or connect a GitHub repo after setup is finished.

## Next Step

Open \`01 Projects/Agent Setup Tutorial/project.md\` and work through the tutorial project with your agent.
EOF

cat > "$VAULT_DIR/90 Ops/Service Map.md" <<EOF
# Service Map

## Purpose

This file maps external platforms to the workflows they support so agent prompts stay grounded in real tools instead of generic role language.

EOF

i=0
while [[ $i -lt $SERVICE_COUNT ]]; do
  {
    printf '## %s\n\n' "${SERVICE_NAMES[$i]}"
    printf 'What the user does there: %s\n\n' "${SERVICE_USES[$i]}"
    printf 'Mapped workflow: %s\n\n' "${SERVICE_WORKFLOW_MAPS[$i]}"
  } >> "$VAULT_DIR/90 Ops/Service Map.md"
  i=$((i + 1))
done

cat > "$AGENT_SOURCE_DIR/agent-candidates.md" <<EOF
# Agent Candidates

These are the first agents the system should build and refine.

## Core Workflow Agents

- $WORKFLOW_1_TITLE
- $WORKFLOW_2_TITLE

## Why These

- they are repeatable
- they have named triggers
- they touch explicit systems
- they are good candidates for durable instructions

## Service-Grounded Refinement

EOF

i=0
while [[ $i -lt $SERVICE_COUNT ]]; do
  {
    printf -- '- %s feeds workflow %s because the user uses it for %s\n' \
      "${SERVICE_NAMES[$i]}" \
      "${SERVICE_WORKFLOW_MAPS[$i]}" \
      "${SERVICE_USES[$i]}"
  } >> "$AGENT_SOURCE_DIR/agent-candidates.md"
  i=$((i + 1))
done

cat > "$TUTORIAL_DIR/project.md" <<EOF
# Agent Setup Tutorial

## Goal

Turn this blank vault into a usable working system for $USER_NAME.

## Chosen Platforms

$(printf -- '- %s\n' "${PLATFORMS[@]}")

## Starter Workflows

- $WORKFLOW_1_TITLE: $WORKFLOW_1_SUMMARY
- $WORKFLOW_2_TITLE: $WORKFLOW_2_SUMMARY

## Service Scope

$(i=0; while [[ $i -lt $SERVICE_COUNT ]]; do printf -- '- %s: %s\n' "${SERVICE_NAMES[$i]}" "${SERVICE_USES[$i]}"; i=$((i + 1)); done)

## Outcome Definition

This project is complete when:

- at least one workflow agent is fully customized
- Git is initialized and the setup is committed
- GitHub is either connected or explicitly deferred
- at least one external service is connected
- the next real project is ready to run through the system
EOF

cat > "$TUTORIAL_DIR/tasks.md" <<EOF
# Tasks

## Orientation

EOF
append_task "$TUTORIAL_DIR/tasks.md" "Read \`90 Ops/First Run.md\`."
append_task "$TUTORIAL_DIR/tasks.md" "Review \`90 Ops/Service Map.md\` and correct anything too vague."
append_task "$TUTORIAL_DIR/tasks.md" "Review \`HEARTBEAT.md\` and \`90 Ops/Heartbeat Config.md\`."
append_task "$TUTORIAL_DIR/tasks.md" "Choose which workflow should become the first fully usable agent."

printf '\n## Services\n\n' >> "$TUTORIAL_DIR/tasks.md"
i=0
while [[ $i -lt $SERVICE_COUNT ]]; do
  append_task "$TUTORIAL_DIR/tasks.md" "Connect or validate access to ${SERVICE_NAMES[$i]}."
  i=$((i + 1))
done

printf '\n## Git And GitHub\n\n' >> "$TUTORIAL_DIR/tasks.md"
append_task "$TUTORIAL_DIR/tasks.md" "Initialize Git if needed."
append_task "$TUTORIAL_DIR/tasks.md" "Create the initial setup commit."
append_task "$TUTORIAL_DIR/tasks.md" "Create or connect the GitHub repo."

printf '\n## Recurring Review\n\n' >> "$TUTORIAL_DIR/tasks.md"
append_task "$TUTORIAL_DIR/tasks.md" "Confirm the recurring review cadence and quiet-mode settings."
append_task "$TUTORIAL_DIR/tasks.md" "Choose how the recurring review mechanism will actually run on the selected platform(s)."

printf '\n## Validation\n\n' >> "$TUTORIAL_DIR/tasks.md"
append_task "$TUTORIAL_DIR/tasks.md" "Run one real task through the first workflow agent."
append_task "$TUTORIAL_DIR/tasks.md" "Record what the agent needed but did not have."
append_task "$TUTORIAL_DIR/tasks.md" "Create the next project that this system should support."

cat > "$TUTORIAL_DIR/log.md" <<EOF
# Log

- Setup initialized for $USER_NAME.
- Platforms selected: $(printf '%s' "${PLATFORMS[*]}")
- Services selected: $(printf '%s ' "${SERVICE_NAMES[@]}")
- Recurring review enabled: $HEARTBEAT_ENABLED
EOF

cat > "$TUTORIAL_DIR/decisions.md" <<EOF
# Decisions

- This vault will be used as the durable operating layer for agent work.
- Agents should be defined around repeatable workflows before expanding into more specialized roles.
- Service usage should shape agent prompts so they are grounded in real work rather than abstract roles.
- Recurring review should stay lightweight and quiet by default.
EOF

create_openclaw_sources() {
  local title="$1"
  local slug="$2"
  local summary="$3"
  local workflow_number="$4"
  local source_root="$AGENT_SOURCE_DIR/OpenClaw/$slug"
  write_file_from_template \
    "$TEMPLATES_DIR/openclaw/AGENTS.md.template" \
    "$source_root/AGENTS.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
  append_workflow_context "$source_root/AGENTS.md" "$title" "$summary" "$workflow_number" "$SERVICE_COUNT"
  write_file_from_template \
    "$TEMPLATES_DIR/openclaw/BOOTSTRAP.md.template" \
    "$source_root/BOOTSTRAP.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
  write_openclaw_heartbeat "$source_root/HEARTBEAT.md" "$title" "$slug"
}

create_claude_sources() {
  local title="$1"
  local slug="$2"
  local summary="$3"
  local workflow_number="$4"
  write_file_from_template \
    "$TEMPLATES_DIR/claude-code/subagent.md.template" \
    "$AGENT_SOURCE_DIR/Claude Code/$slug.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
  append_workflow_context "$AGENT_SOURCE_DIR/Claude Code/$slug.md" "$title" "$summary" "$workflow_number" "$SERVICE_COUNT"
}

create_codex_sources() {
  local title="$1"
  local slug="$2"
  local summary="$3"
  local workflow_number="$4"
  write_file_from_template \
    "$TEMPLATES_DIR/codex-skill/SKILL.md.template" \
    "$AGENT_SOURCE_DIR/Codex Skills/$slug/SKILL.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
  append_workflow_context "$AGENT_SOURCE_DIR/Codex Skills/$slug/SKILL.md" "$title" "$summary" "$workflow_number" "$SERVICE_COUNT"
}

create_chatgpt_sources() {
  local title="$1"
  local slug="$2"
  local summary="$3"
  local workflow_number="$4"
  write_file_from_template \
    "$TEMPLATES_DIR/chatgpt/custom-gpt.md.template" \
    "$AGENT_SOURCE_DIR/ChatGPT GPTs/$slug.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
  append_workflow_context "$AGENT_SOURCE_DIR/ChatGPT GPTs/$slug.md" "$title" "$summary" "$workflow_number" "$SERVICE_COUNT"
}

for platform in "${PLATFORMS[@]}"; do
  case "$platform" in
    openclaw)
      create_openclaw_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG" "$WORKFLOW_1_SUMMARY" "1"
      create_openclaw_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG" "$WORKFLOW_2_SUMMARY" "2"
      if prompt_yes_no "Also deploy live OpenClaw workspaces now?" "n"; then
        OPENCLAW_ROOT="$(prompt_default "OpenClaw workspaces path" "$HOME/openclaw agents/workspaces")"
        ensure_dir "$OPENCLAW_ROOT/$WORKFLOW_1_SLUG"
        ensure_dir "$OPENCLAW_ROOT/$WORKFLOW_2_SLUG"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_1_SLUG/AGENTS.md" "$OPENCLAW_ROOT/$WORKFLOW_1_SLUG/AGENTS.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_1_SLUG/BOOTSTRAP.md" "$OPENCLAW_ROOT/$WORKFLOW_1_SLUG/BOOTSTRAP.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_1_SLUG/HEARTBEAT.md" "$OPENCLAW_ROOT/$WORKFLOW_1_SLUG/HEARTBEAT.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_2_SLUG/AGENTS.md" "$OPENCLAW_ROOT/$WORKFLOW_2_SLUG/AGENTS.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_2_SLUG/BOOTSTRAP.md" "$OPENCLAW_ROOT/$WORKFLOW_2_SLUG/BOOTSTRAP.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_2_SLUG/HEARTBEAT.md" "$OPENCLAW_ROOT/$WORKFLOW_2_SLUG/HEARTBEAT.md"
      fi
      ;;
    claude)
      create_claude_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG" "$WORKFLOW_1_SUMMARY" "1"
      create_claude_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG" "$WORKFLOW_2_SUMMARY" "2"
      if prompt_yes_no "Also deploy Claude Code subagents into this project now?" "n"; then
        ensure_dir "$VAULT_DIR/.claude/agents"
        cp "$AGENT_SOURCE_DIR/Claude Code/$WORKFLOW_1_SLUG.md" "$VAULT_DIR/.claude/agents/$WORKFLOW_1_SLUG.md"
        cp "$AGENT_SOURCE_DIR/Claude Code/$WORKFLOW_2_SLUG.md" "$VAULT_DIR/.claude/agents/$WORKFLOW_2_SLUG.md"
      fi
      ;;
    codex)
      create_codex_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG" "$WORKFLOW_1_SUMMARY" "1"
      create_codex_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG" "$WORKFLOW_2_SUMMARY" "2"
      if prompt_yes_no "Also deploy Codex skills into ~/.codex/skills now?" "n"; then
        ensure_dir "$HOME/.codex/skills/$WORKFLOW_1_SLUG"
        ensure_dir "$HOME/.codex/skills/$WORKFLOW_2_SLUG"
        cp "$AGENT_SOURCE_DIR/Codex Skills/$WORKFLOW_1_SLUG/SKILL.md" "$HOME/.codex/skills/$WORKFLOW_1_SLUG/SKILL.md"
        cp "$AGENT_SOURCE_DIR/Codex Skills/$WORKFLOW_2_SLUG/SKILL.md" "$HOME/.codex/skills/$WORKFLOW_2_SLUG/SKILL.md"
      fi
      ;;
    chatgpt)
      create_chatgpt_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG" "$WORKFLOW_1_SUMMARY" "1"
      create_chatgpt_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG" "$WORKFLOW_2_SUMMARY" "2"
      ;;
    *)
      echo "Skipping unknown platform: $platform"
      ;;
  esac
done

setup_github_remote

echo
echo "Setup complete."
echo
echo "Start here:"
echo "- $VAULT_DIR/90 Ops/First Run.md"
echo "- $VAULT_DIR/90 Ops/Service Map.md"
echo "- $TUTORIAL_DIR/project.md"
echo "- $TUTORIAL_DIR/tasks.md"
echo
echo "Source workflow agents were created under:"
echo "- $AGENT_SOURCE_DIR"
