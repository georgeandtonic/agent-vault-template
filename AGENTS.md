# AGENTS.md - Agent Vault Operating Rules

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
