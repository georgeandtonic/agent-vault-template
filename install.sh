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

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/-\{2,\}/-/g' \
    | sed 's/^-//' \
    | sed 's/-$//'
}

ensure_dir() {
  mkdir -p "$1"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
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

echo
echo "Agent Vault guided setup"
echo
echo "This setup will help you:"
echo "- understand what the vault is for"
echo "- choose the right agent runtime(s)"
echo "- define two real workflows"
echo "- scaffold platform-specific agent definitions"
echo "- create a tutorial project for tool and system setup"
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
  platform="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]' | xargs)"
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
SYSTEMS_INPUT="$(prompt_default "Systems to connect later (comma-separated)" "GitHub,Google Workspace,Notion")"

WORKFLOW_1_SLUG="$(slugify "$WORKFLOW_1_TITLE")"
WORKFLOW_2_SLUG="$(slugify "$WORKFLOW_2_TITLE")"

VAULT_DIR="$ROOT_DIR"
AGENT_SOURCE_DIR="$VAULT_DIR/90 Ops/Agents"
TUTORIAL_DIR="$VAULT_DIR/01 Projects/Agent Setup Tutorial"

ensure_dir "$AGENT_SOURCE_DIR/OpenClaw"
ensure_dir "$AGENT_SOURCE_DIR/Claude Code"
ensure_dir "$AGENT_SOURCE_DIR/Codex Skills"
ensure_dir "$AGENT_SOURCE_DIR/ChatGPT GPTs"
ensure_dir "$TUTORIAL_DIR"

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

Good examples:

- planning a week
- triaging inbound work
- reviewing documents
- building and validating code

Each workflow should answer:

1. What triggers it?
2. What context does it need first?
3. What systems does it touch?
4. What must be written down when it is done?

## Platforms Chosen

$(printf -- '- %s\n' "${PLATFORMS[@]}")

## Initial Workflows

1. $WORKFLOW_1_TITLE
   Summary: $WORKFLOW_1_SUMMARY
2. $WORKFLOW_2_TITLE
   Summary: $WORKFLOW_2_SUMMARY

## Systems To Connect

$SYSTEMS_INPUT

## Next Step

Open \`01 Projects/Agent Setup Tutorial/project.md\` and work through the tutorial project with your agent.
EOF

cat > "$TUTORIAL_DIR/project.md" <<EOF
# Agent Setup Tutorial

## Goal

Turn this blank vault into a usable working system for $USER_NAME.

## Chosen Platforms

$(printf -- '- %s\n' "${PLATFORMS[@]}")

## Starter Workflows

- $WORKFLOW_1_TITLE: $WORKFLOW_1_SUMMARY
- $WORKFLOW_2_TITLE: $WORKFLOW_2_SUMMARY

## Outcome Definition

This project is complete when:

- at least one workflow agent is fully customized
- at least one external system is connected
- the next real project is ready to run through the system
EOF

cat > "$TUTORIAL_DIR/tasks.md" <<EOF
# Tasks

## Orientation

EOF
append_task "$TUTORIAL_DIR/tasks.md" "Read \`90 Ops/First Run.md\`."
append_task "$TUTORIAL_DIR/tasks.md" "Review the two starter workflows and rewrite them if they are too broad."
append_task "$TUTORIAL_DIR/tasks.md" "Choose which workflow should become the first fully usable agent."

printf "\n## Systems\n\n" >> "$TUTORIAL_DIR/tasks.md"
IFS=',' read -r -a SYSTEMS <<< "$SYSTEMS_INPUT"
for system_name in "${SYSTEMS[@]}"; do
  trimmed_system="$(printf '%s' "$system_name" | xargs)"
  if [[ -n "$trimmed_system" ]]; then
    append_task "$TUTORIAL_DIR/tasks.md" "Connect or validate access to $trimmed_system."
  fi
done

printf "\n## Validation\n\n" >> "$TUTORIAL_DIR/tasks.md"
append_task "$TUTORIAL_DIR/tasks.md" "Run one real task through the first workflow agent."
append_task "$TUTORIAL_DIR/tasks.md" "Record what the agent needed but did not have."
append_task "$TUTORIAL_DIR/tasks.md" "Create the next project that this system should support."

cat > "$TUTORIAL_DIR/log.md" <<EOF
# Log

- Setup initialized for $USER_NAME.
- Platforms selected: $(printf '%s' "${PLATFORMS[*]}")
- Systems queued: $SYSTEMS_INPUT
EOF

cat > "$TUTORIAL_DIR/decisions.md" <<EOF
# Decisions

- This vault will be used as the durable operating layer for agent work.
- Agents should be defined around repeatable workflows before expanding into more specialized roles.
EOF

create_openclaw_sources() {
  local title="$1"
  local slug="$2"
  local source_root="$AGENT_SOURCE_DIR/OpenClaw/$slug"
  write_file_from_template \
    "$TEMPLATES_DIR/openclaw/AGENTS.md.template" \
    "$source_root/AGENTS.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
  write_file_from_template \
    "$TEMPLATES_DIR/openclaw/BOOTSTRAP.md.template" \
    "$source_root/BOOTSTRAP.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
}

create_claude_sources() {
  local title="$1"
  local slug="$2"
  write_file_from_template \
    "$TEMPLATES_DIR/claude-code/subagent.md.template" \
    "$AGENT_SOURCE_DIR/Claude Code/$slug.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
}

create_codex_sources() {
  local title="$1"
  local slug="$2"
  write_file_from_template \
    "$TEMPLATES_DIR/codex-skill/SKILL.md.template" \
    "$AGENT_SOURCE_DIR/Codex Skills/$slug/SKILL.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
}

create_chatgpt_sources() {
  local title="$1"
  local slug="$2"
  write_file_from_template \
    "$TEMPLATES_DIR/chatgpt/custom-gpt.md.template" \
    "$AGENT_SOURCE_DIR/ChatGPT GPTs/$slug.md" \
    "$title" \
    "$slug" \
    "$VAULT_DIR"
}

for platform in "${PLATFORMS[@]}"; do
  case "$platform" in
    openclaw)
      create_openclaw_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG"
      create_openclaw_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG"
      if prompt_yes_no "Also deploy live OpenClaw workspaces now?" "n"; then
        OPENCLAW_ROOT="$(prompt_default "OpenClaw workspaces path" "$HOME/openclaw agents/workspaces")"
        ensure_dir "$OPENCLAW_ROOT/$WORKFLOW_1_SLUG"
        ensure_dir "$OPENCLAW_ROOT/$WORKFLOW_2_SLUG"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_1_SLUG/AGENTS.md" "$OPENCLAW_ROOT/$WORKFLOW_1_SLUG/AGENTS.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_1_SLUG/BOOTSTRAP.md" "$OPENCLAW_ROOT/$WORKFLOW_1_SLUG/BOOTSTRAP.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_2_SLUG/AGENTS.md" "$OPENCLAW_ROOT/$WORKFLOW_2_SLUG/AGENTS.md"
        cp "$AGENT_SOURCE_DIR/OpenClaw/$WORKFLOW_2_SLUG/BOOTSTRAP.md" "$OPENCLAW_ROOT/$WORKFLOW_2_SLUG/BOOTSTRAP.md"
      fi
      ;;
    claude)
      create_claude_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG"
      create_claude_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG"
      if prompt_yes_no "Also deploy Claude Code subagents into this project now?" "n"; then
        ensure_dir "$VAULT_DIR/.claude/agents"
        cp "$AGENT_SOURCE_DIR/Claude Code/$WORKFLOW_1_SLUG.md" "$VAULT_DIR/.claude/agents/$WORKFLOW_1_SLUG.md"
        cp "$AGENT_SOURCE_DIR/Claude Code/$WORKFLOW_2_SLUG.md" "$VAULT_DIR/.claude/agents/$WORKFLOW_2_SLUG.md"
      fi
      ;;
    codex)
      create_codex_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG"
      create_codex_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG"
      if prompt_yes_no "Also deploy Codex skills into ~/.codex/skills now?" "n"; then
        ensure_dir "$HOME/.codex/skills/$WORKFLOW_1_SLUG"
        ensure_dir "$HOME/.codex/skills/$WORKFLOW_2_SLUG"
        cp "$AGENT_SOURCE_DIR/Codex Skills/$WORKFLOW_1_SLUG/SKILL.md" "$HOME/.codex/skills/$WORKFLOW_1_SLUG/SKILL.md"
        cp "$AGENT_SOURCE_DIR/Codex Skills/$WORKFLOW_2_SLUG/SKILL.md" "$HOME/.codex/skills/$WORKFLOW_2_SLUG/SKILL.md"
      fi
      ;;
    chatgpt)
      create_chatgpt_sources "$WORKFLOW_1_TITLE" "$WORKFLOW_1_SLUG"
      create_chatgpt_sources "$WORKFLOW_2_TITLE" "$WORKFLOW_2_SLUG"
      ;;
    *)
      echo "Skipping unknown platform: $platform"
      ;;
  esac
done

echo
echo "Setup complete."
echo
echo "Start here:"
echo "- $VAULT_DIR/90 Ops/First Run.md"
echo "- $TUTORIAL_DIR/project.md"
echo "- $TUTORIAL_DIR/tasks.md"
echo
echo "Source workflow agents were created under:"
echo "- $AGENT_SOURCE_DIR"
