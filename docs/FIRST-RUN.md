# First-Run Experience

The installer is meant to do more than create folders. It should orient the user and turn vague intent into real working structure.

## What The User Learns

The first run should explain:

- what the vault is for
- how the vault, agents, and systems fit together
- why agents should be built around repeatable workflows instead of job titles
- which platform-specific format applies to their stack

## What The User Chooses

The guided setup asks for:

- the user's name
- which platform(s) they want to use
- two repeatable workflows they want help with
- which systems they expect to connect, such as GitHub, Notion, Google Workspace, Slack, Salesforce, or local files

## What The Installer Creates

- a personalized `90 Ops/First Run.md`
- source-of-truth workflow definitions under `90 Ops/Agents/`
- platform-specific agent scaffolds in the right format
- an `Agent Setup Tutorial` project with concrete next steps

## Why Two Workflows

Two workflows are enough to force specificity without turning setup into a giant planning exercise. Good examples:

- weekly planning
- inbound request triage
- customer support follow-up
- document review
- coding and validation
- research and synthesis

## Tutorial Project Outcome

The tutorial project should end with:

- at least one working agent definition
- at least one connected system or tool
- a clear next project to tackle with the agent
