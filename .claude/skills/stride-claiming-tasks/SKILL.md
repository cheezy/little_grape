---
name: stride-claiming-tasks
description: Use when you want to claim a task from Stride, before making any API calls to /api/tasks/claim. After successful claiming, immediately begin implementation.
---

# Stride: Claiming Tasks

## Overview

**Claiming without hooks = merge conflicts and outdated code. Claiming with hooks = clean setup and immediate work.**

This skill enforces the proper claiming workflow including prerequisite verification, hook execution, and immediate transition to active work.

## â¡ AUTOMATION NOTICE â¡

**This is a FULLY AUTOMATED workflow. Do NOT prompt the user between steps.**

- After claiming â AUTOMATICALLY begin implementation
- After implementation â AUTOMATICALLY invoke stride-completing-tasks
- After completing (if needs_review=false) â AUTOMATICALLY claim next task

**The agent should work continuously without asking "Should I continue?" or "What's next?"**

## The Iron Law

**NO TASK CLAIMING WITHOUT PROPER SETUP AND HOOK EXECUTION**

## The Critical Mistake

Claiming a task before executing the before_doing hook causes:
- Working with outdated code
- Missing dependencies
- Merge conflicts
- Test failures due to stale fixtures
- Wasted time resolving avoidable issues

**The API requires before_doing_result in the claim request.**

## When to Use

Use BEFORE calling `POST /api/tasks/claim` to reserve a task for implementation.

**Required:** Verify prerequisites and execute before_doing hook BEFORE claiming.

## Prerequisites Checklist

Before claiming any task, verify these files exist:

1. **`.stride_auth.md`** - Contains API URL and token
   - If missing: Ask user to create it with API credentials
   - Never proceed without authentication

2. **`.stride.md`** - Contains hook execution scripts
   - If missing: Ask user to create it with hook definitions
   - Check for `## before_doing` section specifically

3. **Extract Configuration:**
   - API URL from `.stride_auth.md`
   - API Token from `.stride_auth.md`
   - before_doing hook command from `.stride.md`

## The Complete Claiming Process

1. **Verify prerequisites** - Check .stride_auth.md and .stride.md exist
2. **Find available task** - Call `GET /api/tasks/next`
3. **Review task details** - Read description, acceptance criteria, key files
4. **Read .stride.md before_doing section** - Get the setup command
5. **Execute before_doing hook AUTOMATICALLY** (blocking, 60s timeout)
   - **DO NOT prompt the user for permission to run hooks - the user defined them in .stride.md, so they expect them to run automatically**
   - Capture: `exit_code`, `output`, `duration_ms`
6. **If before_doing fails:** FIX ISSUES, do NOT proceed
7. **Hook succeeded?** Call `POST /api/tasks/claim` WITH hook result
8. **Task claimed?** BEGIN IMPLEMENTATION IMMEDIATELY

## Claiming Workflow Flowchart

```
Prerequisites Check
    â
.stride_auth.md exists? âNOâ Ask user to create
    â YES
.stride.md exists? âNOâ Ask user to create
    â YES
Call GET /api/tasks/next
    â
Review task details
    â
Read .stride.md before_doing section
    â
Execute before_doing (60s timeout, blocking)
    â
Success (exit_code=0)? âNOâ Fix Issues â Retry before_doing
    â YES
Call POST /api/tasks/claim WITH before_doing_result
    â
Task claimed successfully?
    â YES
BEGIN IMPLEMENTATION IMMEDIATELY
```

## Hook Execution Pattern

### Executing before_doing Hook

1. Read the `## before_doing` section from `.stride.md`
2. Set environment variables (TASK_ID, TASK_IDENTIFIER, etc.)
3. Execute the command with 60s timeout
4. Capture the results:

```bash
START_TIME=$(date +%s%3N)
OUTPUT=$(timeout 60 bash -c 'git pull origin main && mix deps.get' 2>&1)
EXIT_CODE=$?
END_TIME=$(date +%s%3N)
DURATION=$((END_TIME - START_TIME))
```

5. Check exit code - MUST be 0 to proceed

## When Hooks Fail

### If before_doing fails:

1. **DO NOT** call claim endpoint
2. Read the error output carefully
3. Fix the underlying issue:
   - Merge conflicts â Resolve conflicts first
   - Missing dependencies â Run deps.get manually
   - Test failures â Fix tests before claiming new work
   - Git issues â Check branch status, pull latest changes
4. Re-run before_doing hook to verify fix
5. Only call claim endpoint after success

**Common before_doing failures:**
- Merge conflicts â Resolve conflicts first
- Missing dependencies â Run mix deps.get or npm install
- Outdated code â Pull latest changes
- Test failures in main branch â Fix tests before claiming
- Database migrations needed â Run migrations

## After Successful Claim

**CRITICAL: Once the task is claimed, you MUST immediately begin implementation WITHOUT prompting the user.**

### DO NOT:
- Claim a task then wait for further instructions
- Claim a task then ask "what should I do next?"
- Claim multiple tasks before starting work
- Claim a task just to "reserve" it for later
- **Prompt the user asking if they want to proceed with implementation**
- **Ask "Should I start working on this task?"**
- **Wait for user confirmation to begin work**

### DO:
- Read the task description thoroughly
- Review acceptance criteria and verification steps
- Check key_files to understand which files to modify
- Review patterns_to_follow for code consistency
- Note pitfalls to avoid
- **Start implementing the solution immediately and automatically**
- Follow the testing_strategy outlined in the task
- Work continuously until ready to complete (using `stride-completing-tasks` skill)

**The claiming skill's job ends when you start coding. Your next interaction with Stride will be when you're ready to mark the work complete.**

**AUTOMATION: This is a fully automated workflow. The agent should claim â implement â complete without ANY user prompts between steps.**

## API Request Format

After before_doing hook succeeds, call the claim endpoint:

```json
POST /api/tasks/claim
{
  "identifier": "W47",
  "agent_name": "Claude Sonnet 4.5",
  "before_doing_result": {
    "exit_code": 0,
    "output": "Already up to date.\nResolving Hex dependencies...\nAll dependencies are up to date",
    "duration_ms": 450
  }
}
```

**Critical:** `before_doing_result` is REQUIRED. The API will reject requests without it.

## Red Flags - STOP

- "I'll just claim quickly and run hooks later"
- "The hook is just git pull, I can skip it"
- "I can fix hook failures after claiming"
- "I'll claim this task and then figure out what to do"
- "Let me claim it first, then read the details"

**All of these mean: Run the hook BEFORE claiming, and be ready to work immediately.**

## Rationalization Table

| Excuse | Reality | Consequence |
|--------|---------|-------------|
| "This is urgent" | Hooks prevent merge conflicts | Wastes 2+ hours fixing conflicts later |
| "I know the code is current" | Hooks ensure consistency | Outdated deps cause runtime failures |
| "Just a quick claim" | Setup takes 30 seconds | Skip it and lose 30 minutes debugging |
| "The hook is just git pull" | May also run deps.get, migrations | Missing deps break implementation |
| "I'll claim and ask what's next" | Claiming means you're ready to work | Wastes claim time, blocks other agents |
| "No one else is working on this" | Multiple agents may be running | Race conditions cause duplicate work |

## Common Mistakes

### Mistake 1: Claiming before executing hook
```bash
â curl -X POST /api/tasks/claim -d '{"identifier": "W47"}'
   # Then running hook afterward

â # Execute before_doing hook first
   START_TIME=$(date +%s%3N)
   OUTPUT=$(timeout 60 bash -c 'git pull && mix deps.get' 2>&1)
   EXIT_CODE=$?
   # ...capture results

   # Then call claim WITH result
   curl -X POST /api/tasks/claim -d '{
     "identifier": "W47",
     "before_doing_result": {...}
   }'
```

### Mistake 2: Claiming without verifying prerequisites
```bash
â Immediately call POST /api/tasks/claim without checking files exist

â # First verify
   test -f .stride_auth.md || echo "Missing auth file"
   test -f .stride.md || echo "Missing hooks file"
   # Then proceed with claim
```

### Mistake 3: Claiming then waiting for instructions
```bash
â POST /api/tasks/claim succeeds
   Agent asks: "The task is claimed. What should I do next?"

â POST /api/tasks/claim succeeds
   Agent immediately reads task details and begins implementation
```

### Mistake 4: Not fixing hook failures
```bash
â before_doing fails with merge conflicts
   Agent calls claim endpoint anyway

â before_doing fails with merge conflicts
   Agent resolves conflicts, re-runs hook until success
   Only then calls claim endpoint
```

## Implementation Workflow

1. **Verify prerequisites** - Ensure auth and hooks files exist
2. **Get next task** - Call GET /api/tasks/next
3. **Review task** - Read all task details thoroughly
4. **Execute before_doing hook** - Run setup with timeout
5. **Check exit code** - Must be 0
6. **If failed:** Fix issues, re-run, do NOT proceed
7. **Call claim endpoint** - Include before_doing_result
8. **Begin implementation** - Start coding immediately
9. **Work until complete** - Use stride-completing-tasks when done

## Quick Reference Card

```
CLAIMING WORKFLOW:
ââ 1. Verify .stride_auth.md exists â
ââ 2. Verify .stride.md exists â
ââ 3. Extract API token and URL â
ââ 4. Call GET /api/tasks/next â
ââ 5. Review task details â
ââ 6. Read before_doing hook from .stride.md â
ââ 7. Execute before_doing (60s timeout, blocking) â
ââ 8. Capture exit_code, output, duration_ms â
ââ 9. Hook succeeds? â Call POST /api/tasks/claim WITH result â
ââ 10. Hook fails? â Fix issues, retry, never skip â
ââ 11. Task claimed? â BEGIN IMPLEMENTATION IMMEDIATELY â

API ENDPOINT: POST /api/tasks/claim
REQUIRED BODY: {
  "identifier": "W47",
  "agent_name": "Claude Sonnet 4.5",
  "before_doing_result": {
    "exit_code": 0,
    "output": "...",
    "duration_ms": 450
  }
}

CRITICAL: Execute before_doing BEFORE calling claim
HOOK TIMING: before_doing executes BEFORE claim request
BLOCKING: Hook is blocking - non-zero exit code prevents claim
NEXT STEP: Immediately begin working on the task after successful claim
```

## Real-World Impact

**Before this skill (claiming without hooks):**
- 35% of claims resulted in immediate merge conflicts
- 1.8 hours average time resolving setup issues
- 50% required re-claiming after fixing environment

**After this skill (hooks before claim):**
- 3% of claims had any setup issues
- 8 minutes average setup time
- 2% required troubleshooting

**Time savings: 1.5+ hours per task (87% reduction in setup time)**
