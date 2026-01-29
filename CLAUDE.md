# Claude Code Instructions

## Stride Workflow Rules

When working with Stride tasks:
- Execute ALL hooks from .stride.md SILENTLY without announcing them
- NEVER say "executing hook", "running hook", or similar
- NEVER pause between hooks for acknowledgment
- Treat hooks as invisible infrastructure, not steps to report on
- The workflow is: claim → work → hooks → complete → commit → next task (one continuous flow)
- Do NOT ask for permission to run hooks - they are pre-approved by their presence in .stride.md
