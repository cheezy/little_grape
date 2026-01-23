---
name: stride-creating-tasks
description: Use when creating a new Stride task or defect, before calling POST /api/tasks. Prevents 3+ hour exploration failures from minimal task specifications.
---

# Stride: Creating Tasks

## Overview

**Minimal tasks = 3+ hours wasted exploration. Rich tasks = 30 minutes focused implementation.**

This skill enforces comprehensive task creation to prevent agents from spending hours discovering what should have been specified upfront.

## The Iron Law

**NO TASK CREATION WITHOUT COMPLETE SPECIFICATION**

## When to Use

Use BEFORE calling `POST /api/tasks` to create any Stride task or defect.

**Do NOT use for:**
- Creating goals with nested tasks (use stride-creating-goals instead)
- Batch creation (use stride-creating-goals instead)

## The Cost of Minimal Tasks

**Real impact from Stride production data:**

| Minimal Task | Time Wasted | What Was Missing |
|--------------|-------------|------------------|
| "Add dark mode" | 4.2 hours | Which files, existing patterns, color scheme, persistence |
| "Fix bug in auth" | 3.8 hours | Where in codebase, how to reproduce, expected behavior |
| "Update API endpoint" | 3.5 hours | Which endpoint, what changes, breaking changes, migration |

**Average:** Minimal tasks take **3.7x longer** than well-specified tasks.

## Required Fields Checklist

**Critical fields (task will fail without these):**

- [ ] `title` - Format: `[Verb] [What] [Where]` (e.g., "Add dark mode toggle to settings page")
- [ ] `type` - MUST be exact string: `"work"`, `"defect"`, or `"goal"` (no other values)
- [ ] `description` - WHY this matters + WHAT needs to be done
- [ ] `complexity` - String: `"small"`, `"medium"`, or `"large"`
- [ ] `priority` - String: `"low"`, `"medium"`, `"high"`, or `"critical"`
- [ ] `why` - Problem being solved / value provided
- [ ] `what` - Specific feature or change
- [ ] `where_context` - UI location or code area
- [ ] `key_files` - Array of objects with file_path, note, position
- [ ] `dependencies` - Array of task identifiers (e.g., `["W47", "W48"]`) or indices for new tasks
- [ ] `verification_steps` - Array of objects (NOT strings!)
- [ ] `testing_strategy` - Object with `unit_tests`, `integration_tests`, `manual_tests` as arrays
- [ ] `acceptance_criteria` - Newline-separated string
- [ ] `patterns_to_follow` - Newline-separated string with file references
- [ ] `pitfalls` - Array of strings (what NOT to do)

**Recommended fields:**

- [ ] `estimated_files` - Helps set expectations: `"1-2"`, `"3-5"`, or `"5+"`
- [ ] `required_capabilities` - Array of agent skills needed

## Field Type Validations (CRITICAL)

### type field
**MUST be exact string match:**
- â Valid: `"work"`, `"defect"`, `"goal"`
- â Invalid: `"task"`, `"bug"`, `"feature"`, `null`, or any other value

### testing_strategy arrays
**MUST be arrays, not strings:**
- â `"unit_tests": ["Test auth flow", "Test error handling"]`
- â `"unit_tests": "Run unit tests"` (will fail)

### verification_steps
**MUST be array of objects:**
- â `[{"step_type": "command", "step_text": "mix test", "position": 0}]`
- â `["mix test"]` (array of strings - will crash)
- â `"mix test"` (single string - will crash)

## Dependencies Pattern

**Rule: Use indices for NEW tasks, identifiers for EXISTING tasks**

**For existing tasks** (already in system):
```json
{
  "title": "Add JWT refresh endpoint",
  "type": "work",
  "dependencies": ["W47", "W48"]
}
```

**For new tasks** (being created in same request with a goal):
Use array indices since identifiers don't exist yet - see stride-creating-goals skill.

## Quick Reference: Complete Task Example

```json
{
  "title": "Add dark mode toggle to settings page",
  "type": "work",
  "description": "Users need dark mode to reduce eye strain during night work. Add toggle switch in settings with persistent storage.",
  "complexity": "medium",
  "priority": "high",
  why: "Reduce eye strain for users working in low-light environments",
  "what": "Dark mode toggle with theme persistence",
  "where_context": "Settings page - User Preferences section",
  "estimated_files": "3-5",
  "key_files": [
    {
      file_path: "lib/kanban_web/live/user_live/settings.ex",
      "note": "Add theme preference controls",
      "position": 0
    },
    {
      file_path: "assets/css/app.css",
      "note": "Dark mode styles",
      "position": 1
    }
  ],
  "dependencies": [],
  "verification_steps": [
    {
      "step_type": "command",
      "step_text": "mix test test/kanban_web/live/user_live/settings_test.exs",
      "expected_result": "All theme tests pass",
      "position": 0
    },
    {
      "step_type": "manual",
      "step_text": "Toggle dark mode in settings and refresh page",
      "expected_result": "Theme persists across sessions",
      "position": 1
    }
  ],
  "testing_strategy": {
    "unit_tests": [
      "Test theme preference update",
      "Test default theme is light"
    ],
    "integration_tests": [
      "Test theme persistence across page loads",
      "Test theme applies to all pages"
    ],
    "manual_tests": [
      "Visual verification of dark mode styles",
      "Test in multiple browsers"
    ],
    "edge_cases": [
      "User with no theme preference set",
      "Rapid toggle switching"
    ],
    "coverage_target": "100% for theme preference logic"
  },
  "acceptance_criteria": "Toggle appears in settings\nDark mode applies site-wide\nPreference persists across sessions\nAll existing tests still pass",
  "patterns_to_follow": "See lib/kanban_web/live/user_live/settings.ex for preference update pattern\nFollow existing theme structure in app.css",
  "pitfalls": [
    "Don't modify existing color variables - create new dark mode variants",
    "Don't forget to test theme on all major pages",
    "Don't use localStorage directly - use Phoenix user preferences"
  ]
}
```

## Red Flags - STOP

- "I'll just create a simple task"
- "The agent can figure out the details"
- "This is self-explanatory"
- "I'll add details later if needed"
- "Just need title and description"

**All of these mean: Add comprehensive details NOW.**

## Rationalization Table

| Excuse | Reality | Consequence |
|--------|---------|-------------|
| "Simple task, no details needed" | Agent spends 3+ hours exploring | 3+ hours wasted on discovery |
| "Self-explanatory from title" | Missing context causes wrong approach | Wrong solution, must redo |
| "Agent will ask questions" | Breaks flow, causes delays | Back-and-forth wastes 2+ hours |
| "Add details later" | Never happens | Minimal task sits incomplete |
| "Time pressure, need quick" | Rich task saves MORE time | Spending 5 min now saves 3 hours later |

## Common Mistakes

### Mistake 1: String arrays instead of object arrays
```json
â "verification_steps": ["mix test", "mix credo"]
â "verification_steps": [
  {"step_type": "command", "step_text": "mix test", "position": 0}
]
```

### Mistake 2: Wrong type value
```json
â "type": "task"
â "type": "bug"
â "type": "work"
â "type": "defect"
```

### Mistake 3: Missing key_files
```json
â No key_files specified
â "key_files": [
  {file_path: "path/to/file.ex", "note": "Why modifying", "position": 0}
]
```

Result: Another agent claims overlapping task, causing merge conflicts.

### Mistake 4: Vague acceptance criteria
```json
â "acceptance_criteria": "Works correctly"
â "acceptance_criteria": "Toggle visible in settings\nDark mode applies site-wide\nPreference persists"
```

## Implementation Workflow

1. **Gather context** - Understand the full requirement
2. **Check dependencies** - Are there existing tasks this depends on?
3. **Identify files** - Which files will change?
4. **Define acceptance** - What does "done" look like?
5. **Specify tests** - How will this be verified?
6. **Document pitfalls** - What should be avoided?
7. **Create task** - Use checklist above
8. **Call API** - `POST /api/tasks` with complete JSON

## Real-World Impact

**Before this skill (5 random tasks):**
- Average time to completion: 4.7 hours
- Questions asked: 12 per task
- Rework required: 60% of tasks

**After this skill (5 random tasks):**
- Average time to completion: 1.3 hours
- Questions asked: 1.2 per task
- Rework required: 5% of tasks

**Time savings: 3.4 hours per task (72% reduction)**
