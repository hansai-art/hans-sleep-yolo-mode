---
name: autonomous-skill
description: Use when user wants to execute long-running tasks. Trigger phrases: "autonomous", "自主執行", "long-running task".
---

# Autonomous Skill

Execute complex tasks across multiple sessions without losing context.

## Directory Structure
```
.autonomous/<task-name>/
├── task_list.md    # Tasks with checkboxes
├── progress.md     # Session notes / blockers / decisions
└── logs/           # Optional command output or runner logs
```

## When To Use
- Multi-hour implementation work
- Tasks that naturally decompose into many small checkpoints
- Work that may require retries, pauses, or multiple Claude sessions

## Core Rules
1. Break the work into small, testable checklist items.
2. Finish one item completely before moving to the next.
3. Record decisions, blockers, and retries in `progress.md`.
4. Re-run relevant tests before marking a step done.
5. Commit after meaningful progress so the work can resume safely later.

## Task List Best Practices
- Use 10-30 concrete checkbox items.
- Each item should be completable in roughly 5-15 minutes.
- Prefer outcome-based tasks, not vague reminders.
- Include setup, implementation, validation, and cleanup steps.
- If a task is blocked, add a new checkbox for the fallback path instead of stalling.

## Session Workflow
1. Read `task_list.md` and `progress.md`.
2. Pick the first unfinished checkbox.
3. Implement only the current slice of work.
4. Validate the change with the existing test or verification flow.
5. Mark the checkbox done and append a short progress note.
6. Commit with a descriptive message before ending the session.

## Handoff Notes
Use `progress.md` to capture:
- what changed
- what remains
- commands/tests already run
- known risks or assumptions
- exact blocker details if something failed

## Usage
- Start: "Please use autonomous skill to [description]"
- Continue: "Continue the autonomous task [task-name]"
