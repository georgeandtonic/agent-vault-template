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
