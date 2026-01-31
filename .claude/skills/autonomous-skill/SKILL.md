---
name: autonomous-skill
description: Use when user wants to execute long-running tasks. Trigger phrases: "autonomous", "自主執行", "long-running task".
---

# Autonomous Skill

Execute complex tasks across multiple sessions.

## Directory Structure
```
.autonomous/<task-name>/
├── task_list.md    # Tasks with checkboxes
└── progress.md     # Session notes
```

## Usage
- Start: "Please use autonomous skill to [description]"
- Continue: "Continue the autonomous task [task-name]"
