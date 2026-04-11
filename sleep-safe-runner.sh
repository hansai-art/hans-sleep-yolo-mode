#!/bin/bash
# ============================================
# 🌙 Sleep-Safe Autonomous Runner v3.1
# 全自動執行，可以安心睡覺
# ============================================
#
# 用法：
#   ./sleep-safe-runner.sh "任務名稱" "任務詳細說明（可選）"
#   ./sleep-safe-runner.sh --status "任務名稱"    # 查看進度
#   ./sleep-safe-runner.sh --status-json "任務名稱" # 以 JSON 輸出狀態
#   ./sleep-safe-runner.sh --list                 # 列出所有任務
#   ./sleep-safe-runner.sh --list-presets         # 列出可用 preset
#   ./sleep-safe-runner.sh --preset feature "任務名稱" "任務詳細說明"
#   ./sleep-safe-runner.sh --doctor               # 檢查環境與設定
#   ./sleep-safe-runner.sh --notify-test          # 測試通知設定
#   ./sleep-safe-runner.sh --repair "任務名稱"    # 修復遺失的任務檔案
#
# ============================================

set -euo pipefail

validate_task_name() {
    local task_name="$1"

    [[ -n "$task_name" ]] || return 1
    [[ "$task_name" != -* ]] || return 1
    [[ "$task_name" != "." && "$task_name" != ".." ]] || return 1
    [[ "$task_name" != *"/"* ]] || return 1
    [[ "$task_name" != *"\\"* ]] || return 1
    [[ "$task_name" != *$'\n'* ]] || return 1
    [[ "$task_name" != *$'\r'* ]] || return 1

    return 0
}

get_timeout_bin() {
    if command -v timeout &>/dev/null; then
        echo "timeout"
    elif command -v gtimeout &>/dev/null; then
        echo "gtimeout"
    else
        echo ""
    fi
}

json_escape() {
    local escaped="${1//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//$'\n'/\\n}"
    escaped="${escaped//$'\r'/\\r}"
    escaped="${escaped//$'\t'/\\t}"
    escaped="${escaped//$'\f'/\\f}"
    escaped="${escaped//$'\b'/\\b}"
    printf '%s' "$escaped"
}

strip_ansi_codes() {
    sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

get_runner_username() {
    local runner_user=""

    runner_user="$(id -un 2>/dev/null || true)"
    if [[ -z "$runner_user" && -n "${USER:-}" ]]; then
        runner_user="$USER"
    fi
    if [[ -z "$runner_user" ]]; then
        printf '%s\n' "Unable to determine current user for temporary runner paths" >&2
        exit 1
    fi

    printf '%s' "$runner_user"
}

create_runner_temp_file() {
    local prefix="$1"
    local tmp_file
    local temp_dir_user="${RUNNER_USER:-}"

    if [[ -z "$temp_dir_user" ]]; then
        temp_dir_user="$(get_runner_username 2>/dev/null || printf 'runner')"
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/${TEMP_PATH_PREFIX}-${temp_dir_user}-${prefix}.XXXXXX")" || {
        printf '%s\n' "Failed to create temporary file for ${prefix}" >&2
        return 1
    }

    printf '%s' "$tmp_file"
}

create_runner_temp_dir() {
    local tmp_dir

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/${TEMP_PATH_PREFIX}-${RUNNER_USER}.XXXXXX")" || {
        printf '%s\n' "Failed to create temporary runner directory" >&2
        exit 1
    }

    printf '%s' "$tmp_dir"
}

atomic_replace_file_from_command() {
    local target_file="$1"
    local prefix="$2"
    local error_message="$3"
    shift 3

    local tmp_file
    tmp_file="$(create_runner_temp_file "$prefix")" || return 1

    "$@" > "$tmp_file" || {
        log "$error_message" "ERROR"
        rm -f "$tmp_file"
        return 1
    }

    mv "$tmp_file" "$target_file" || {
        log "$error_message" "ERROR"
        rm -f "$tmp_file"
        return 1
    }
}

extract_json_line_fields() {
    local json_line="$1"
    shift

    JSON_LINE="$json_line" JSON_ERROR_EXCERPT_LENGTH="$JSON_ERROR_EXCERPT_LENGTH" python - "$@" <<'PY'
import json
import os
import sys

raw_line = os.environ["JSON_LINE"]

try:
    data = json.loads(raw_line)
except Exception as exc:
    excerpt = raw_line[:int(os.environ["JSON_ERROR_EXCERPT_LENGTH"])].replace("\n", "\\n")
    print(f"Warning: Unable to parse status history JSON line. Error: {exc}. Excerpt: {excerpt}", file=sys.stderr)
    sys.exit(0)

values = []
for key in sys.argv[1:]:
    value = data.get(key, "")
    values.append(value if isinstance(value, str) else "")

sys.stdout.write("\t".join(values))
PY
}

path_has_symlink_component() {
    python - "$1" <<'PY'
import os
import sys

path = os.path.abspath(sys.argv[1])
parts = path.split(os.sep)
current = os.sep if path.startswith(os.sep) else parts[0]
start = 1 if path.startswith(os.sep) else 0

for part in parts[start:]:
    if not part:
        continue
    current = os.path.join(current, part) if current != os.sep else os.path.join(os.sep, part)
    if os.path.islink(current):
        print("true")
        sys.exit(0)

print("false")
PY
}

cleanup_file_if_present() {
    local path="$1"
    [[ -n "$path" ]] && rm -f "$path"
}

run_with_captured_stderr() {
    local output_var_name="$1"
    shift

    local stderr_file=""
    local stderr_output=""
    stderr_file="$(create_runner_temp_file "stderr")" || return 1
    if "$@" 2>"$stderr_file"; then
        cleanup_file_if_present "$stderr_file"
        printf -v "$output_var_name" '%s' ""
        return 0
    fi

    stderr_output="$(cat "$stderr_file" 2>/dev/null || true)"
    cleanup_file_if_present "$stderr_file"
    printf -v "$output_var_name" '%s' "$stderr_output"
    return 1
}

apple_escape() {
    local escaped="${1//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '%s' "$escaped"
}

to_branch_slug() {
    local slug
    slug="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9._-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^[._-]*//' -e 's/[._-]*$//')"
    [[ -n "$slug" ]] || slug="task"
    printf '%s' "$slug"
}

readonly PROTECTED_BRANCHES=(main master) # Add more protected branches here if needed.
readonly FAILURE_SIGNAL_PATTERN='Session failed|Too many consecutive failures|Failed to create task list|timed out|notification failed|Runner stopped|Claude CLI not found|Not a git repository'
readonly STATUS_ARTIFACT_VERSION=2
readonly STATUS_RECENT_ITEMS_LIMIT=5
readonly STATUS_HISTORY_LIMIT=8
readonly JSON_ERROR_EXCERPT_LENGTH=120
readonly TEMP_PATH_PREFIX="hans-sleep-yolo-mode"
readonly MKTEMP_SUFFIX_GLOB='[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]*'
readonly TASK_LIST_ITEM_PATTERN='^\s*- \['
readonly TASK_COMPLETED_PATTERN='^\s*- \[x\]'
readonly TASK_PENDING_PATTERN='^\s*- \[ \]'
readonly AVAILABLE_PRESETS=(bugfix feature refactor docs repo-setup)
readonly CORE_INSTALL_FILES=(
    "CLAUDE.md"
    "setup-wizard.sh"
    "sleep-safe-runner.sh"
    ".sleep-yolo.env.example"
    ".sleep-yolo.team.example.json"
    ".claude/settings.json"
    ".claude/skills/autonomous-skill/SKILL.md"
)

is_protected_branch() {
    local branch="$1"
    local protected_branch

    for protected_branch in "${PROTECTED_BRANCHES[@]}"; do
        [[ "$branch" == "$protected_branch" ]] && return 0
    done

    return 1
}

all_core_files_present() {
    local path

    for path in "${CORE_INSTALL_FILES[@]}"; do
        [[ -f "$path" ]] || return 1
    done

    return 0
}

list_missing_core_files() {
    local path
    local missing=()

    for path in "${CORE_INSTALL_FILES[@]}"; do
        [[ -f "$path" ]] || missing+=("$path")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        printf 'none'
    else
        join_with_commas "${missing[@]}"
    fi
}

join_with_commas() {
    if [[ "$#" -eq 0 ]]; then
        printf ''
        return 0
    fi

    local joined="$1"
    shift

    local item
    for item in "$@"; do
        joined+=", $item"
    done

    printf '%s' "$joined"
}

task_progress_file_path() {
    printf '.autonomous/%s/progress.md' "$1"
}

task_status_file_path() {
    printf '.autonomous/%s/status.json' "$1"
}

task_history_file_path() {
    printf '.autonomous/%s/status-history.jsonl' "$1"
}

task_metadata_file_path() {
    printf '.autonomous/%s/task-metadata.json' "$1"
}

bool_string() {
    if [[ "${1:-}" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

iso_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

list_available_presets() {
    printf '%s\n' "${AVAILABLE_PRESETS[@]}"
}

is_supported_preset() {
    local preset="$1"
    [[ "$preset" == "custom" ]] && return 0

    local available_preset
    for available_preset in "${AVAILABLE_PRESETS[@]}"; do
        [[ "$preset" == "$available_preset" ]] && return 0
    done

    return 1
}

get_preset_summary() {
    case "$1" in
        bugfix) printf 'Bug fix flow with reproduction, targeted patch, and regression validation.' ;;
        feature) printf 'Feature delivery flow with discovery, implementation, tests, and rollout notes.' ;;
        refactor) printf 'Refactor flow focused on safe structural change plus verification.' ;;
        docs) printf 'Documentation flow for content updates, examples, and accuracy review.' ;;
        repo-setup) printf 'Repository setup flow for tooling, automation, and onboarding foundations.' ;;
        *) printf 'Custom task flow decided at runtime.' ;;
    esac
}

get_preset_init_context() {
    case "$1" in
        bugfix)
            cat <<'EOF'
Preset: bugfix
- Start from reproduction and observed failure scope
- Identify the smallest safe fix
- Add or update regression coverage
- Validate the original failure is resolved
EOF
            ;;
        feature)
            cat <<'EOF'
Preset: feature
- Confirm requirements and affected surfaces
- Implement incrementally in small reviewable steps
- Add tests and docs for the new behavior
- Include rollout or follow-up notes when relevant
EOF
            ;;
        refactor)
            cat <<'EOF'
Preset: refactor
- Preserve existing behavior while improving structure
- Prefer small, reversible moves
- Keep verification close to each change
- Call out any deferred cleanup explicitly
EOF
            ;;
        docs)
            cat <<'EOF'
Preset: docs
- Identify the exact audience and doc surface to update
- Refresh examples and command snippets
- Verify the documentation matches current behavior
- Highlight any remaining manual follow-up items
EOF
            ;;
        repo-setup)
            cat <<'EOF'
Preset: repo-setup
- Establish install/setup flow first
- Add required config and automation scaffolding
- Document onboarding and validation steps
- Leave the repo in a ready-to-start state
EOF
            ;;
        *)
            printf ''
            ;;
    esac
}

write_preset_task_list() {
    local preset="$1"
    local task_file="$2"
    local task_name="$3"
    local task_description="$4"

    case "$preset" in
        bugfix)
            cat > "$task_file" <<EOF
# Task: $task_name
Preset: bugfix
${task_description:+Description: $task_description}

- [ ] Reproduce the bug and capture the failing path
- [ ] Identify the smallest safe fix in the affected code
- [ ] Implement the bug fix
- [ ] Add or update regression coverage
- [ ] Verify the failing path now passes
- [ ] Review logs, cleanup, and finalize
EOF
            ;;
        feature)
            cat > "$task_file" <<EOF
# Task: $task_name
Preset: feature
${task_description:+Description: $task_description}

- [ ] Review the current code paths and define the feature scope
- [ ] Break the feature into small implementation steps
- [ ] Implement the first slice of the feature
- [ ] Complete the remaining feature work
- [ ] Add or update tests for the new behavior
- [ ] Update docs or usage notes if needed
- [ ] Validate the full feature flow
EOF
            ;;
        refactor)
            cat > "$task_file" <<EOF
# Task: $task_name
Preset: refactor
${task_description:+Description: $task_description}

- [ ] Map the current structure and define safe refactor boundaries
- [ ] Make the first structural cleanup without behavior changes
- [ ] Continue the refactor in small reversible steps
- [ ] Remove obsolete code or duplication
- [ ] Run validation to confirm behavior is unchanged
- [ ] Document any follow-up cleanup and finalize
EOF
            ;;
        docs)
            cat > "$task_file" <<EOF
# Task: $task_name
Preset: docs
${task_description:+Description: $task_description}

- [ ] Identify the docs, examples, and commands that need updates
- [ ] Draft the main documentation changes
- [ ] Refresh examples, snippets, and onboarding steps
- [ ] Verify the docs match current project behavior
- [ ] Proofread and finalize the documentation update
EOF
            ;;
        repo-setup)
            cat > "$task_file" <<EOF
# Task: $task_name
Preset: repo-setup
${task_description:+Description: $task_description}

- [ ] Review the repository setup gaps and desired developer workflow
- [ ] Add or update install/setup automation
- [ ] Add or update required config and scaffolding
- [ ] Document the recommended onboarding steps
- [ ] Validate the setup flow end to end
- [ ] Finalize with cleanup and follow-up notes
EOF
            ;;
        *)
            cat > "$task_file" <<EOF
# Task: $task_name
${task_description:+Description: $task_description}

- [ ] Analyze the codebase and understand current structure
- [ ] Plan implementation approach
- [ ] Implement the feature
- [ ] Write tests
- [ ] Verify tests pass
- [ ] Clean up and finalize
EOF
            ;;
    esac
}

write_task_metadata_file() {
    local task_name="$1"
    local task_description="$2"
    local task_preset="$3"
    local metadata_file="$4"
    local started_at="$5"
    local updated_at="$6"

    mkdir -p "$(dirname "$metadata_file")"
    cat > "$metadata_file" <<EOF
{
  "version": 1,
  "task": "$(json_escape "$task_name")",
  "description": "$(json_escape "$task_description")",
  "preset": "$(json_escape "$task_preset")",
  "presetSummary": "$(json_escape "$(get_preset_summary "$task_preset")")",
  "statusArtifactVersion": $STATUS_ARTIFACT_VERSION,
  "startedAt": "$(json_escape "$started_at")",
  "updatedAt": "$(json_escape "$updated_at")",
  "paths": {
    "taskFile": "$(json_escape "$TASK_FILE")",
    "progressFile": "$(json_escape "$PROGRESS_FILE")",
    "statusFile": "$(json_escape "$STATUS_FILE")",
    "historyFile": "$(json_escape "$HISTORY_FILE")"
  },
  "team": {
    "sharedPreset": "",
    "sharedNotificationsPolicy": "",
    "protectedBranchPolicy": {
      "branches": $(json_string_array_from_args "${PROTECTED_BRANCHES[@]}"),
      "requireFeatureBranch": true
    },
    "auditSchema": "task-status-v$STATUS_ARTIFACT_VERSION"
  }
}
EOF
}

get_task_metadata_json() {
    local metadata_file="$1"
    if [[ -f "$metadata_file" ]]; then
        cat "$metadata_file"
    else
        printf '{"version":1,"task":"%s","description":"%s","preset":"%s","presetSummary":"%s"}' \
            "$(json_escape "$TASK_NAME")" \
            "$(json_escape "${TASK_DESCRIPTION:-}")" \
            "$(json_escape "${TASK_PRESET:-custom}")" \
            "$(json_escape "$(get_preset_summary "${TASK_PRESET:-custom}")")"
    fi
}

extract_json_string_field() {
    local file="$1"
    local key="$2"
    [[ -f "$file" ]] || return 0
    python - "$file" "$key" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]

try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    print(f"warning: Unable to parse JSON file {path}: {exc}. Check file syntax or run --repair to regenerate.", file=sys.stderr)
    sys.exit(0)

value = data.get(key, "")
if isinstance(value, str):
    sys.stdout.write(value)
PY
}

extract_task_file_field() {
    local task_file="$1"
    local key="$2"
    [[ -f "$task_file" ]] || return 0
    sed -n "s/^${key}: //p" "$task_file" | head -1
}

load_task_file_metadata() {
    local task_file="$1"
    local preset
    local description

    [[ -f "$task_file" ]] || return 0

    preset="$(extract_task_file_field "$task_file" "Preset")"
    description="$(extract_task_file_field "$task_file" "Description")"

    if [[ -n "$preset" && "$TASK_PRESET" == "custom" ]] && is_supported_preset "$preset"; then
        TASK_PRESET="$preset"
    fi

    if [[ -n "$description" && -z "${TASK_DESCRIPTION:-}" ]]; then
        TASK_DESCRIPTION="$description"
    fi
}

load_existing_task_metadata() {
    local metadata_file="$1"
    local preset
    local description

    [[ -f "$metadata_file" ]] || return 0

    preset="$(extract_json_string_field "$metadata_file" "preset")"
    description="$(extract_json_string_field "$metadata_file" "description")"

    if [[ -n "$preset" ]] && is_supported_preset "$preset"; then
        TASK_PRESET="$preset"
    fi

    if [[ -n "$description" && -z "${TASK_DESCRIPTION:-}" ]]; then
        TASK_DESCRIPTION="$description"
    fi
}

get_task_counts() {
    local task_file="$1"
    local total=0
    local done=0
    local pending=0
    local pct=0

    if [[ -f "$task_file" ]]; then
        IFS='|' read -r done total pending pct < <(
            awk '
                BEGIN { done = 0; total = 0 }
                /^[[:space:]]*- \[[ x]\]/ {
                    total++
                    if ($0 ~ /^[[:space:]]*- \[x\]/) {
                        done++
                    }
                }
                END {
                    pending = total - done
                    pct = total > 0 ? int((done * 100) / total) : 0
                    printf "%s|%s|%s|%s\n", done, total, pending, pct
                }
            ' "$task_file"
        )
    fi

    printf '%s|%s|%s|%s' "$done" "$total" "$pending" "$pct"
}

get_task_state() {
    local task_file="$1"
    local counts
    local done
    local total

    if [[ ! -f "$task_file" ]]; then
        printf 'missing'
        return 0
    fi

    counts="$(get_task_counts "$task_file")"
    IFS='|' read -r done total _ _ <<< "$counts"

    if [[ "$total" -eq 0 ]]; then
        printf 'initialized'
    elif [[ "$done" -eq "$total" ]]; then
        printf 'completed'
    elif [[ "$done" -eq 0 ]]; then
        printf 'planned'
    else
        printf 'in_progress'
    fi
}

get_recent_completed_lines() {
    local task_file="$1"
    [[ -f "$task_file" ]] || return 0
    { grep "$TASK_COMPLETED_PATTERN" "$task_file" || true; } | tail -"$STATUS_RECENT_ITEMS_LIMIT" | sed 's/^\s*- \[x\] /✓ /'
}

get_next_up_lines() {
    local task_file="$1"
    [[ -f "$task_file" ]] || return 0
    { grep "$TASK_PENDING_PATTERN" "$task_file" || true; } | head -"$STATUS_RECENT_ITEMS_LIMIT" | sed 's/^\s*- \[ \] /• /'
}

get_progress_summary_lines() {
    local progress_file="$1"
    [[ -f "$progress_file" ]] || return 0

    awk '
        NF && $0 !~ /^#/ {
            line=$0
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
            lines[++count]=line
        }
        END {
            start=(count > limit ? count - limit + 1 : 1)
            for (i = start; i <= count; i++) print lines[i]
        }
    ' limit="$STATUS_RECENT_ITEMS_LIMIT" "$progress_file"
}

get_recent_log_lines() {
    local log_dir="$1"
    [[ -f "$log_dir/runner.log" ]] || return 0
    tail -6 "$log_dir/runner.log" | strip_ansi_codes
}

get_recent_failure_signal() {
    local log_dir="$1"
    local runner_log="$log_dir/runner.log"
    [[ -f "$runner_log" ]] || return 0

    { tail -100 "$runner_log" | strip_ansi_codes | grep -E "$FAILURE_SIGNAL_PATTERN" || true; } | tail -1
}

get_recent_checkpoints_lines() {
    local task_name="$1"
    git log --oneline -"${STATUS_RECENT_ITEMS_LIMIT}" --format="%h %s" 2>/dev/null | grep -F -e "checkpoint" -e "$task_name" || true
}

json_array_from_stream() {
    local first=true
    local line

    printf '['
    while IFS= read -r line; do
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '"%s"' "$(json_escape "$line")"
    done
    printf ']'
}

json_string_array_from_args() {
    local first=true
    local item

    printf '['
    for item in "$@"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '"%s"' "$(json_escape "$item")"
    done
    printf ']'
}

json_object_array_from_stream() {
    local first=true
    local line

    printf '['
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '%s' "$line"
    done
    printf ']'
}

get_latest_checkpoint_line() {
    local task_name="$1"
    get_recent_checkpoints_lines "$task_name" | tail -1
}

detect_failure_category() {
    local signal="$1"

    if [[ -z "$signal" ]]; then
        printf 'none'
    elif [[ "$signal" == *"Claude CLI not found"* ]]; then
        printf 'cli_missing'
    elif [[ "$signal" == *"Not a git repository"* ]]; then
        printf 'git_repository'
    elif [[ "$signal" == *"Failed to create task list"* ]]; then
        printf 'task_initialization'
    elif [[ "$signal" == *"timed out"* || "$signal" == *"Session timed out"* ]]; then
        printf 'timeout'
    elif [[ "$signal" == *"notification failed"* || "$signal" == *"All notification delivery attempts failed"* ]]; then
        printf 'notification_failed'
    elif [[ "$signal" == *"Session failed (exit code:"* ]]; then
        printf 'claude_non_zero_exit'
    elif [[ "$signal" == *"Too many consecutive failures"* ]]; then
        printf 'repeated_failures'
    elif [[ "$signal" == *"Runner stopped"* ]]; then
        printf 'runner_stopped'
    else
        printf 'unknown'
    fi
}

get_failure_details() {
    local signal="$1"
    local category
    local summary="$signal"
    local hint=""
    local failure_task_name="${TASK_NAME:-task}"
    local failure_log_dir="${LOG_DIR:-.autonomous/$failure_task_name/logs}"

    category="$(detect_failure_category "$signal")"

    case "$category" in
        none)
            summary=""
            hint=""
            ;;
        cli_missing)
            summary="Claude CLI is missing."
            hint="Install it with: npm install -g @anthropic-ai/claude-code"
            ;;
        git_repository)
            summary="Current directory is not a git repository."
            hint="Run inside a git repo or initialize one with git init."
            ;;
        task_initialization)
            summary="Task bootstrap failed."
            hint="Run ./sleep-safe-runner.sh --repair \"$failure_task_name\" to recreate task_list.md and progress.md, then retry."
            ;;
        timeout)
            summary="A Claude session timed out before finishing."
            hint="Reduce task scope or increase MAX_SESSION_MINUTES in .sleep-yolo.env."
            ;;
        notification_failed)
            summary="Configured notification providers could not deliver."
            hint="Run ./sleep-safe-runner.sh --notify-test and review .sleep-yolo.env provider settings."
            ;;
        claude_non_zero_exit)
            summary="Claude exited with a non-zero status."
            hint="Inspect the latest session log under $failure_log_dir and retry the task."
            ;;
        repeated_failures)
            summary="Runner stopped after repeated failures."
            hint="Review the latest failure below, repair the issue, then resume the same task."
            ;;
        runner_stopped)
            summary="Runner was stopped before completion."
            hint="Resume with ./sleep-safe-runner.sh \"$failure_task_name\"."
            ;;
        *)
            hint="Inspect runner.log for the latest error details."
            ;;
    esac

    printf '%s|%s|%s' "$category" "$summary" "$hint"
}

get_failure_object_json() {
    local signal="$1"
    local parts
    local category
    local summary
    local hint

    parts="$(get_failure_details "$signal")"
    IFS='|' read -r category summary hint <<< "$parts"

    printf '{'
    printf '"category":"%s",' "$(json_escape "$category")"
    printf '"summary":"%s",' "$(json_escape "$summary")"
    printf '"actionHint":"%s",' "$(json_escape "$hint")"
    printf '"signal":"%s"' "$(json_escape "$signal")"
    printf '}'
}

collect_repair_hints() {
    local task_name="$1"
    local task_file="$2"
    local progress_file="$3"
    local current_branch=""

    if [[ ! -f "$task_file" ]]; then
        printf '%s\n' "Run ./sleep-safe-runner.sh --repair \"$task_name\" to recreate task_list.md and progress.md."
    elif [[ ! -f "$progress_file" ]]; then
        printf '%s\n' "Run ./sleep-safe-runner.sh --repair \"$task_name\" to restore the missing progress.md file."
    fi

    if [[ ! -f "$(task_metadata_file_path "$task_name")" ]]; then
        printf '%s\n' "Run ./sleep-safe-runner.sh --repair \"$task_name\" to restore task metadata and preset info."
    fi

    if git rev-parse --git-dir &>/dev/null; then
        current_branch=$(git branch --show-current 2>/dev/null || echo "")
        if [[ -n "$current_branch" ]] && is_protected_branch "$current_branch"; then
            printf '%s\n' "Create a feature branch before overnight runs: git checkout -b auto/$(to_branch_slug "$task_name")."
        fi
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            printf '%s\n' "Commit or stash local changes before running overnight automation."
        fi
    fi

    if ! all_core_files_present; then
        printf '%s\n' "Restore missing core files by rerunning install.sh ($(list_missing_core_files))."
    fi
}

get_recent_history_entries() {
    local history_file="$1"
    [[ -f "$history_file" ]] || return 0
    tail -n "$STATUS_HISTORY_LIMIT" "$history_file"
}

get_task_started_at() {
    local status_file="$1"
    local history_file="$2"
    local started_at=""
    local first_history_line=""

    started_at="$(extract_json_string_field "$status_file" "startedAt")"
    if [[ -z "$started_at" && -f "$history_file" ]]; then
        first_history_line="$(head -1 "$history_file" 2>/dev/null || true)"
        if [[ -n "$first_history_line" ]]; then
            started_at="$(extract_json_line_fields "$first_history_line" "timestamp")"
        fi
    fi
    if [[ -z "$started_at" ]]; then
        started_at="$(iso_timestamp)"
    fi

    printf '%s' "$started_at"
}

append_task_history_entry() {
    local phase="$1"
    local history_file="$2"
    local counts
    local done
    local total
    local pending
    local pct
    local state
    local failure_signal
    local failure_parts
    local category
    local summary
    local hint
    local latest_summary
    local latest_completed
    local next_up
    mkdir -p "$(dirname "$history_file")"

    counts="$(get_task_counts "$TASK_FILE")"
    IFS='|' read -r done total pending pct <<< "$counts"
    state="$(get_task_state "$TASK_FILE")"
    failure_signal="$(get_recent_failure_signal "$LOG_DIR")"
    failure_parts="$(get_failure_details "$failure_signal")"
    IFS='|' read -r category summary hint <<< "$failure_parts"
    latest_summary="$(get_progress_summary_lines "$PROGRESS_FILE" | tail -1)"
    latest_completed="$(get_recent_completed_lines "$TASK_FILE" | tail -1)"
    next_up="$(get_next_up_lines "$TASK_FILE" | head -1)"

    printf '{' >> "$history_file"
    printf '"timestamp":"%s",' "$(json_escape "$(iso_timestamp)")" >> "$history_file"
    printf '"phase":"%s",' "$(json_escape "$phase")" >> "$history_file"
    printf '"iteration":%s,' "${ITERATION:-0}" >> "$history_file"
    printf '"state":"%s",' "$(json_escape "$state")" >> "$history_file"
    printf '"progress":{"done":%s,"total":%s,"pending":%s,"percent":%s},' "$done" "$total" "$pending" "$pct" >> "$history_file"
    printf '"summary":"%s",' "$(json_escape "$latest_summary")" >> "$history_file"
    printf '"latestCompleted":"%s",' "$(json_escape "$latest_completed")" >> "$history_file"
    printf '"nextUp":"%s",' "$(json_escape "$next_up")" >> "$history_file"
    printf '"failure":{"category":"%s","summary":"%s","actionHint":"%s"}' "$(json_escape "$category")" "$(json_escape "$summary")" "$(json_escape "$hint")" >> "$history_file"
    printf '}\n' >> "$history_file"

    atomic_replace_file_from_command \
        "$history_file" \
        "hans-sleep-yolo-history" \
        "Failed to update status history for $TASK_NAME" \
        tail -n "$STATUS_HISTORY_LIMIT" "$history_file"
}

build_task_status_json() {
    local phase="$1"
    local task_name="$2"
    local task_file="$3"
    local log_dir="$4"
    local progress_file="$5"
    local status_file="$6"
    local history_file="$7"
    local metadata_file="$8"
    local counts
    local done
    local total
    local pending
    local pct
    local state
    local started_at
    local updated_at
    local latest_checkpoint
    local failure_signal
    local summary_json
    local completed_json
    local next_up_json
    local recent_log_json
    local checkpoint_json
    local history_json
    local repair_json
    local failure_json
    local metadata_json

    counts="$(get_task_counts "$task_file")"
    IFS='|' read -r done total pending pct <<< "$counts"
    state="$(get_task_state "$task_file")"
    started_at="$(get_task_started_at "$status_file" "$history_file")"
    updated_at="$(iso_timestamp)"
    latest_checkpoint="$(get_latest_checkpoint_line "$task_name")"
    failure_signal="$(get_recent_failure_signal "$log_dir")"
    summary_json="$(get_progress_summary_lines "$progress_file" | json_array_from_stream)"
    completed_json="$(get_recent_completed_lines "$task_file" | json_array_from_stream)"
    next_up_json="$(get_next_up_lines "$task_file" | json_array_from_stream)"
    recent_log_json="$(get_recent_log_lines "$log_dir" | json_array_from_stream)"
    checkpoint_json="$(get_recent_checkpoints_lines "$task_name" | json_array_from_stream)"
    history_json="$(get_recent_history_entries "$history_file" | json_object_array_from_stream)"
    repair_json="$(collect_repair_hints "$task_name" "$task_file" "$progress_file" | json_array_from_stream)"
    failure_json="$(get_failure_object_json "$failure_signal")"
    metadata_json="$(get_task_metadata_json "$metadata_file")"

    printf '{'
    printf '"version":%s,' "$STATUS_ARTIFACT_VERSION"
    printf '"task":"%s",' "$(json_escape "$task_name")"
    printf '"phase":"%s",' "$(json_escape "$phase")"
    printf '"state":"%s",' "$(json_escape "$state")"
    printf '"taskFileExists":%s,' "$( [[ -f "$task_file" ]] && printf 'true' || printf 'false' )"
    printf '"progressFileExists":%s,' "$( [[ -f "$progress_file" ]] && printf 'true' || printf 'false' )"
    printf '"historyFileExists":%s,' "$( [[ -f "$history_file" ]] && printf 'true' || printf 'false' )"
    printf '"startedAt":"%s",' "$(json_escape "$started_at")"
    printf '"updatedAt":"%s",' "$(json_escape "$updated_at")"
    printf '"progress":{"done":%s,"total":%s,"pending":%s,"percent":%s},' "$done" "$total" "$pending" "$pct"
    printf '"summaryLines":%s,' "$summary_json"
    printf '"recentCompleted":%s,' "$completed_json"
    printf '"nextUp":%s,' "$next_up_json"
    printf '"recentLog":%s,' "$recent_log_json"
    printf '"recentCheckpoints":%s,' "$checkpoint_json"
    printf '"latestCheckpoint":"%s",' "$(json_escape "$latest_checkpoint")"
    printf '"metadata":%s,' "$metadata_json"
    printf '"recentHistory":%s,' "$history_json"
    printf '"repairHints":%s,' "$repair_json"
    printf '"failure":%s,' "$failure_json"
    printf '"paths":{"taskFile":"%s","progressFile":"%s","logDir":"%s","statusFile":"%s","historyFile":"%s","metadataFile":"%s"}' \
        "$(json_escape "$task_file")" \
        "$(json_escape "$progress_file")" \
        "$(json_escape "$log_dir")" \
        "$(json_escape "$status_file")" \
        "$(json_escape "$history_file")" \
        "$(json_escape "$metadata_file")"
    printf '}\n'
}

write_task_status_artifact() {
    local phase="$1"
    local task_name="$2"
    local task_file="$3"
    local log_dir="$4"
    local progress_file="$5"
    local status_file="$6"
    local history_file="$7"
    local metadata_file="$8"

    mkdir -p "$(dirname "$status_file")"
    atomic_replace_file_from_command \
        "$status_file" \
        "hans-sleep-yolo-status" \
        "Failed to write status artifact for $task_name" \
        build_task_status_json "$phase" "$task_name" "$task_file" "$log_dir" "$progress_file" "$status_file" "$history_file" "$metadata_file"
}

record_task_status() {
    local phase="$1"
    local include_history="${2:-false}"

    write_task_status_artifact "$phase" "$TASK_NAME" "$TASK_FILE" "$LOG_DIR" "$PROGRESS_FILE" "$STATUS_FILE" "$HISTORY_FILE" "$METADATA_FILE"
    if [[ "$include_history" == "true" ]]; then
        append_task_history_entry "$phase" "$HISTORY_FILE"
        write_task_status_artifact "$phase" "$TASK_NAME" "$TASK_FILE" "$LOG_DIR" "$PROGRESS_FILE" "$STATUS_FILE" "$HISTORY_FILE" "$METADATA_FILE"
    fi
}

# ============ 狀態查看模式 ============
if [[ "${1:-}" == "--status" ]]; then
    TASK="${2:-my-task}"
    TASK_NAME="$TASK"
    if ! validate_task_name "$TASK"; then
        echo "❌ Invalid task name: $TASK" >&2
        exit 1
    fi
    TASK_FILE=".autonomous/$TASK/task_list.md"
    LOG_DIR=".autonomous/$TASK/logs"
    PROGRESS_FILE="$(task_progress_file_path "$TASK")"
    STATUS_FILE="$(task_status_file_path "$TASK")"
    HISTORY_FILE="$(task_history_file_path "$TASK")"
    METADATA_FILE="$(task_metadata_file_path "$TASK")"
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
    write_task_status_artifact "status_view" "$TASK" "$TASK_FILE" "$LOG_DIR" "$PROGRESS_FILE" "$STATUS_FILE" "$HISTORY_FILE" "$METADATA_FILE"
    COUNTS="$(get_task_counts "$TASK_FILE")"
    IFS='|' read -r DONE TOTAL PENDING PCT <<< "$COUNTS"
    FAILURE_SIGNAL="$(get_recent_failure_signal "$LOG_DIR")"
    FAILURE_PARTS="$(get_failure_details "$FAILURE_SIGNAL")"
    IFS='|' read -r FAILURE_CATEGORY FAILURE_SUMMARY FAILURE_HINT <<< "$FAILURE_PARTS"
    CHECKPOINT_LINES="$(get_recent_checkpoints_lines "$TASK")"
    REPAIR_LINES="$(collect_repair_hints "$TASK" "$TASK_FILE" "$PROGRESS_FILE")"

    echo ""
    echo -e "${CYAN}📊 Status: $TASK${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Artifact: $STATUS_FILE"
    if [[ -f "$METADATA_FILE" ]]; then
        echo "Preset: $(extract_json_string_field "$METADATA_FILE" "preset")"
    fi
    echo "Started: $(get_task_started_at "$STATUS_FILE" "$HISTORY_FILE")"
    echo "Updated: $(extract_json_string_field "$STATUS_FILE" "updatedAt")"
    echo ""

    if [[ -f "$TASK_FILE" ]]; then
        echo -e "Progress: ${GREEN}$DONE${NC}/$TOTAL tasks (${PCT}%)"
        echo "State: $(get_task_state "$TASK_FILE")"
        echo ""

        if [[ -f "$PROGRESS_FILE" ]]; then
            echo "📝 Recent summary:"
            while IFS= read -r line; do
                echo "   $line"
            done < <(get_progress_summary_lines "$PROGRESS_FILE")
            echo ""
        fi

        if [[ $DONE -gt 0 ]]; then
            echo -e "${GREEN}✅ Recently completed:${NC}"
            get_recent_completed_lines "$TASK_FILE" | sed 's/^/   /'
            echo ""
        fi

        if [[ $PENDING -gt 0 ]]; then
            echo -e "${YELLOW}⏳ Next up:${NC}"
            get_next_up_lines "$TASK_FILE" | sed 's/^/   /'
            echo ""
        else
            echo -e "${GREEN}🎉 All tasks completed!${NC}"
            echo ""
        fi
    else
        echo -e "${RED}❌ No task list found. Has the task been started?${NC}"
        echo "   Expected: $TASK_FILE"
        echo ""
    fi

    if [[ -n "$FAILURE_SIGNAL" ]]; then
        echo -e "${YELLOW}⚠️ Recent failure signal:${NC}"
        echo "   $FAILURE_SIGNAL"
        [[ -n "$FAILURE_CATEGORY" && "$FAILURE_CATEGORY" != "none" ]] && echo "   Category: $FAILURE_CATEGORY"
        [[ -n "$FAILURE_SUMMARY" ]] && echo "   Summary: $FAILURE_SUMMARY"
        [[ -n "$FAILURE_HINT" ]] && echo "   Action: $FAILURE_HINT"
        echo ""
    fi

    if [[ -f "$LOG_DIR/runner.log" ]]; then
        echo "📋 Recent log (last 6 lines):"
        get_recent_log_lines "$LOG_DIR" | sed 's/^/   /'
        echo ""
    fi

    echo "📁 Recent checkpoints:"
    if [[ -n "$CHECKPOINT_LINES" ]]; then
        printf '%s\n' "$CHECKPOINT_LINES" | sed 's/^/   /'
    else
        echo "   (none yet)"
    fi
    echo ""

    echo "🕘 Recent session history:"
    if [[ -f "$HISTORY_FILE" ]]; then
        tail -n "$STATUS_HISTORY_LIMIT" "$HISTORY_FILE" | while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            history_fields="$(extract_json_line_fields "$line" "timestamp" "phase" "summary")"
            IFS=$'\t' read -r timestamp phase summary <<< "$history_fields"
            echo "   ${timestamp:-unknown} • ${phase:-unknown}${summary:+ • $summary}"
        done
    else
        echo "   (no session history yet)"
    fi
    echo ""

    if [[ -n "$REPAIR_LINES" ]]; then
        echo "🛠 Repair hints:"
        printf '%s\n' "$REPAIR_LINES" | sed 's/^/   /'
        echo ""
    fi
    exit 0
fi

if [[ "${1:-}" == "--status-json" ]]; then
    TASK="${2:-my-task}"
    TASK_NAME="$TASK"
    if ! validate_task_name "$TASK"; then
        echo "❌ Invalid task name: $TASK" >&2
        exit 1
    fi

    TASK_FILE=".autonomous/$TASK/task_list.md"
    LOG_DIR=".autonomous/$TASK/logs"
    PROGRESS_FILE="$(task_progress_file_path "$TASK")"
    STATUS_FILE="$(task_status_file_path "$TASK")"
    HISTORY_FILE="$(task_history_file_path "$TASK")"
    METADATA_FILE="$(task_metadata_file_path "$TASK")"
    write_task_status_artifact "status_view" "$TASK" "$TASK_FILE" "$LOG_DIR" "$PROGRESS_FILE" "$STATUS_FILE" "$HISTORY_FILE" "$METADATA_FILE"
    cat "$STATUS_FILE"
    exit 0
fi

# ============ 列出所有任務 ============
if [[ "${1:-}" == "--list" ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
    echo ""
    echo -e "${CYAN}📋 Autonomous tasks in this project:${NC}"
    echo ""

    if [[ ! -d ".autonomous" ]]; then
        echo "   No tasks found. Start one with:"
        echo '   ./sleep-safe-runner.sh "task-name" "description"'
        echo ""
        exit 0
    fi

    for dir in .autonomous/*/; do
        task=$(basename "$dir")
        task_file="$dir/task_list.md"
        if [[ -f "$task_file" ]]; then
            counts="$(get_task_counts "$task_file")"
            IFS='|' read -r done total _pending pct <<< "$counts"
            if [[ "$done" -eq "$total" && "$total" -gt 0 ]]; then
                echo -e "   ${GREEN}✅ $task${NC} — $done/$total (完成)"
            else
                echo -e "   ${YELLOW}⏳ $task${NC} — $done/$total (${pct}%)"
            fi
        else
            echo "   📁 $task (初始化中或無任務清單)"
        fi
    done
    echo ""
    exit 0
fi

# ============ 配置區 ============
COMMAND="${1:-}"
TASK_NAME="my-task"
TASK_DESCRIPTION="${2:-}"            # 任務詳細描述（可選，給 Claude 更多 context）
TASK_PRESET="custom"
NOTIFY_TEST_MESSAGE=""
ENV_FILE=".sleep-yolo.env"
TIMEOUT_BIN=""
TASK_BRANCH_SLUG=""
RUNNER_USER="$(get_runner_username)"
TEMP_BASE_DIR=""

case "$COMMAND" in
    --list-presets)
        list_available_presets
        exit 0
        ;;
    --preset)
        TASK_PRESET="${2:-}"
        if [[ -z "$TASK_PRESET" ]]; then
            echo "❌ Missing preset name. Usage: ./sleep-safe-runner.sh --preset <preset> \"task-name\" \"description\"" >&2
            exit 1
        fi
        if ! is_supported_preset "$TASK_PRESET"; then
            mapfile -t available_preset_names < <(list_available_presets)
            echo "❌ Unsupported preset: $TASK_PRESET" >&2
            echo "Available presets: $(join_with_commas "${available_preset_names[@]}")" >&2
            exit 1
        fi
        TASK_NAME="${3:-my-task}"
        TASK_DESCRIPTION="${4:-}"
        if ! validate_task_name "$TASK_NAME"; then
            echo "❌ Invalid task name: $TASK_NAME" >&2
            exit 1
        fi
        TASK_BRANCH_SLUG="$(to_branch_slug "$TASK_NAME")"
        ;;
    --doctor)
        TASK_NAME="doctor"
        TASK_DESCRIPTION=""
        ;;
    --notify-test)
        TASK_NAME="notify-test"
        TASK_DESCRIPTION=""
        if [[ -n "${2:-}" ]]; then
            NOTIFY_TEST_MESSAGE="$2"
        fi
        ;;
    --repair)
        TASK_NAME="${2:-my-task}"
        TASK_DESCRIPTION=""
        if ! validate_task_name "$TASK_NAME"; then
            echo "❌ Invalid task name: $TASK_NAME" >&2
            exit 1
        fi
        TASK_BRANCH_SLUG="$(to_branch_slug "$TASK_NAME")"
        ;;
    *)
        TASK_NAME="${1:-my-task}"
        if ! validate_task_name "$TASK_NAME"; then
            echo "❌ Invalid task name. Avoid leading -, /, \\, newline, and reserved names like . or .." >&2
            exit 1
        fi
        TASK_BRANCH_SLUG="$(to_branch_slug "$TASK_NAME")"
        ;;
esac

is_supported_env_key() {
    case "$1" in
        MAX_ITERATIONS|MAX_CONSECUTIVE_FAILURES|SLEEP_BETWEEN_SESSIONS|MAX_SESSION_MINUTES|MAX_TURNS|CHECKPOINT_EVERY|DISCORD_WEBHOOK|NTFY_TOPIC|TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID|LINE_CHANNEL_ACCESS_TOKEN|LINE_USER_ID|SLACK_WEBHOOK)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_safe_env_value() {
    local value="$1"

    [[ "$value" != *'$('* ]] || return 1
    [[ "$value" != *'${'* ]] || return 1
    [[ "$value" != *'`'* ]] || return 1

    return 0
}

load_env_file() {
    local env_file="${1:-$ENV_FILE}"
    [[ -f "$env_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            echo "Warning: Skipping malformed line in $env_file: $line" >&2
            continue
        fi

        local key="${line%%=*}"
        local value="${line#*=}"

        if ! is_supported_env_key "$key"; then
            echo "Warning: Unsupported key in $env_file: $key" >&2
            continue
        fi

        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        if ! is_safe_env_value "$value"; then
            echo "Warning: Unsafe value skipped for $key in $env_file" >&2
            continue
        fi

        printf -v "$key" '%s' "$value"
        export "$key"
    done < "$env_file"
}

load_env_file

MAX_ITERATIONS="${MAX_ITERATIONS:-100}"                 # 最大循環次數
MAX_CONSECUTIVE_FAILURES="${MAX_CONSECUTIVE_FAILURES:-5}"   # 連續失敗上限
SLEEP_BETWEEN_SESSIONS="${SLEEP_BETWEEN_SESSIONS:-5}"       # 執行間隔（秒）
MAX_SESSION_MINUTES="${MAX_SESSION_MINUTES:-45}"            # 單次 session 超時（分鐘）
MAX_TURNS="${MAX_TURNS:-100}"                               # Claude 每次最大 turns
CHECKPOINT_EVERY="${CHECKPOINT_EVERY:-3}"                   # 每 N 輪自動 commit
LOG_DIR=".autonomous/$TASK_NAME/logs"
TASK_FILE=".autonomous/$TASK_NAME/task_list.md"
PROGRESS_FILE="$(task_progress_file_path "$TASK_NAME")"
STATUS_FILE="$(task_status_file_path "$TASK_NAME")"
HISTORY_FILE="$(task_history_file_path "$TASK_NAME")"
METADATA_FILE="$(task_metadata_file_path "$TASK_NAME")"

if [[ "$COMMAND" == "--doctor" || "$COMMAND" == "--notify-test" ]]; then
    TEMP_BASE_DIR="$(create_runner_temp_dir)"
    LOG_DIR="$TEMP_BASE_DIR/$TASK_NAME/logs"
    TASK_FILE="$TEMP_BASE_DIR/$TASK_NAME/task_list.md"
    PROGRESS_FILE="$TEMP_BASE_DIR/$TASK_NAME/progress.md"
    STATUS_FILE="$TEMP_BASE_DIR/$TASK_NAME/status.json"
    HISTORY_FILE="$TEMP_BASE_DIR/$TASK_NAME/status-history.jsonl"
    METADATA_FILE="$TEMP_BASE_DIR/$TASK_NAME/task-metadata.json"
fi

if [[ "$COMMAND" != "--doctor" && "$COMMAND" != "--notify-test" ]]; then
    load_task_file_metadata "$TASK_FILE"
    load_existing_task_metadata "$METADATA_FILE"
fi

# ============ 通知設定 ============
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
LINE_CHANNEL_ACCESS_TOKEN="${LINE_CHANNEL_ACCESS_TOKEN:-}"
LINE_USER_ID="${LINE_USER_ID:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

# ============ 顏色定義 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============ 初始化 ============
mkdir -p "$LOG_DIR"
FAILURE_COUNT=0
ITERATION=0
START_TIME=$(date +%s)
NOTIFY_LAST_STATUS="unknown"
NOTIFY_LAST_DETAIL=""

cleanup_temp_dir() {
    local symlink_detected
    local expected_dir_pattern

    [[ -n "$TEMP_BASE_DIR" ]] || return 0
    [[ -d "$TEMP_BASE_DIR" ]] || return 0
    symlink_detected="$(path_has_symlink_component "$TEMP_BASE_DIR")"
    # mktemp -d with XXXXXX yields at least six random suffix characters; match that minimum here.
    expected_dir_pattern="${TMPDIR:-/tmp}/${TEMP_PATH_PREFIX}-${RUNNER_USER}.${MKTEMP_SUFFIX_GLOB}"
    if [[ "$TEMP_BASE_DIR" != $expected_dir_pattern || "$symlink_detected" == "true" ]]; then
        log "Refusing to remove unexpected temp directory: $TEMP_BASE_DIR" "WARN"
        return 1
    fi
    rm -rf "$TEMP_BASE_DIR"
}

log() {
    local level="${2:-INFO}"
    local color="$NC"
    case "$level" in
        INFO)    color="$CYAN" ;;
        SUCCESS) color="$GREEN" ;;
        WARN)    color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level]${NC} $1" | tee -a "$LOG_DIR/runner.log"
}

# ============ 通知函數 ============
NOTIFY_PROVIDER_RESULTS=()

reset_notification_results() {
    NOTIFY_PROVIDER_RESULTS=()
}

record_notification_result() {
    local provider="$1"
    local configured="$2"
    local status="$3"
    local detail="$4"
    NOTIFY_PROVIDER_RESULTS+=("${provider}|${configured}|${status}|${detail}")
}

send_macos_notification() {
    local message="$1"
    local apple_message
    local apple_task_name
    local error_output=""
    apple_message=$(apple_escape "$message")
    apple_task_name=$(apple_escape "$TASK_NAME")
    if ! run_with_captured_stderr error_output osascript -e "display notification \"$apple_message\" with title \"Claude Code 🤖\" subtitle \"[$apple_task_name]\"" >/dev/null; then
        printf '%s\n' "${error_output:-osascript failed}" >&2
        return 1
    fi
}

send_notify_send_notification() {
    local message="$1"
    notify-send "Claude Code 🤖 [$TASK_NAME]" "$message" >/dev/null 2>&1
}

send_discord_notification() {
    local message="$1"
    local full_message_json
    full_message_json=$(json_escape "$message")
    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$full_message_json\"}" \
        > /dev/null 2>&1
}

send_ntfy_notification() {
    local message="$1"
    curl -s -X POST "https://ntfy.sh/$NTFY_TOPIC" \
        -H "Title: Claude Code 🤖" \
        -H "Priority: default" \
        -d "$message" \
        > /dev/null 2>&1
}

send_telegram_notification() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$message" \
        > /dev/null 2>&1
}

send_line_notification() {
    local message="$1"
    local full_message_json
    local line_user_id_json
    full_message_json=$(json_escape "$message")
    line_user_id_json=$(json_escape "${LINE_USER_ID:-}")
    curl -s -X POST "https://api.line.me/v2/bot/message/push" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
        -d "{\"to\":\"$line_user_id_json\",\"messages\":[{\"type\":\"text\",\"text\":\"$full_message_json\"}]}" \
        > /dev/null 2>&1
}

send_slack_notification() {
    local message="$1"
    local full_message_json
    full_message_json=$(json_escape "$message")
    curl -s -X POST "$SLACK_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"$full_message_json\"}" \
        > /dev/null 2>&1
}

attempt_notification_provider() {
    local provider="$1"
    local configured="$2"
    local max_attempts="$3"
    local message="$4"
    local sender="$5"
    local attempt=1

    if [[ "$configured" != "true" ]]; then
        record_notification_result "$provider" "false" "skipped" "Not configured"
        return 1
    fi

    while [[ "$attempt" -le "$max_attempts" ]]; do
        if "$sender" "$message"; then
            if [[ "$attempt" -gt 1 ]]; then
                record_notification_result "$provider" "true" "sent" "Delivered on retry $attempt"
            else
                record_notification_result "$provider" "true" "sent" "Delivered"
            fi
            return 0
        fi
        attempt=$((attempt + 1))
        if [[ "$attempt" -le "$max_attempts" ]]; then
            sleep 1
        fi
    done

    record_notification_result "$provider" "true" "failed" "Failed after $max_attempts attempt(s)"
    log "$provider notification failed after $max_attempts attempt(s)" "WARN"
    return 1
}

list_successful_notification_providers() {
    local result
    local providers=()

    for result in "${NOTIFY_PROVIDER_RESULTS[@]}"; do
        IFS='|' read -r provider _configured status _detail <<< "$result"
        [[ "$status" == "sent" ]] && providers+=("$provider")
    done

    if [[ ${#providers[@]} -eq 0 ]]; then
        printf ''
    else
        join_with_commas "${providers[@]}"
    fi
}

print_notification_health_report() {
    local result
    local provider
    local configured
    local status
    local detail
    local icon
    local provider_width=12

    echo ""
    echo -e "${CYAN}📡 Notification provider health${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for result in "${NOTIFY_PROVIDER_RESULTS[@]}"; do
        IFS='|' read -r provider configured status detail <<< "$result"
        [[ ${#provider} -gt "$provider_width" ]] && provider_width=${#provider}
    done

    for result in "${NOTIFY_PROVIDER_RESULTS[@]}"; do
        IFS='|' read -r provider configured status detail <<< "$result"
        case "$status" in
            sent) icon="✅" ;;
            failed) icon="❌" ;;
            skipped) icon="⏭️" ;;
            *) icon="•" ;;
        esac
        printf '%s %-'"$provider_width"'s configured=%-5s %s\n' "$icon" "$provider" "$configured" "$detail"
    done
}

notify() {
    local message="$1"
    local emoji="${2:-🤖}"
    local full_message="$emoji [$TASK_NAME] $message"
    local attempted=0
    local delivered=0
    local delivery_channels=""
    local result
    local configured_count=0
    local discord_configured="false"
    local ntfy_configured="false"
    local telegram_configured="false"
    local line_configured="false"
    local slack_configured="false"

    reset_notification_results
    log "📢 Notification: $message" "INFO"

    # macOS 系統通知（零設定，在電腦螢幕上顯示）
    if [[ "$(uname)" == "Darwin" ]]; then
        attempted=$((attempted + 1))
        if attempt_notification_provider "macOS" "true" "1" "$message" send_macos_notification; then
            delivered=$((delivered + 1))
        fi
    else
        record_notification_result "macOS" "false" "skipped" "Only available on macOS"
    fi

    # Linux 系統通知（如果有安裝 libnotify）
    if [[ "$(uname)" == "Linux" ]] && command -v notify-send &>/dev/null; then
        attempted=$((attempted + 1))
        if attempt_notification_provider "notify-send" "true" "1" "$message" send_notify_send_notification; then
            delivered=$((delivered + 1))
        fi
    else
        record_notification_result "notify-send" "false" "skipped" "notify-send not available"
    fi

    # Discord（已有 Discord 的話最快）
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        discord_configured="true"
        configured_count=$((configured_count + 1))
        attempted=$((attempted + 1))
    fi
    if attempt_notification_provider "Discord" "$(bool_string "$discord_configured")" "2" "$full_message" send_discord_notification; then
        delivered=$((delivered + 1))
    fi

    # ntfy.sh
    if [[ -n "${NTFY_TOPIC:-}" ]]; then
        ntfy_configured="true"
        configured_count=$((configured_count + 1))
        attempted=$((attempted + 1))
    fi
    if attempt_notification_provider "ntfy" "$(bool_string "$ntfy_configured")" "2" "$full_message" send_ntfy_notification; then
        delivered=$((delivered + 1))
    fi

    # Telegram
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        telegram_configured="true"
        configured_count=$((configured_count + 1))
        attempted=$((attempted + 1))
    fi
    if attempt_notification_provider "Telegram" "$(bool_string "$telegram_configured")" "2" "$full_message" send_telegram_notification; then
        delivered=$((delivered + 1))
    fi

    # LINE Messaging API
    if [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" && -n "${LINE_USER_ID:-}" ]]; then
        line_configured="true"
        configured_count=$((configured_count + 1))
        attempted=$((attempted + 1))
    fi
    if attempt_notification_provider "LINE" "$(bool_string "$line_configured")" "2" "$full_message" send_line_notification; then
        delivered=$((delivered + 1))
    fi

    # Slack
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        slack_configured="true"
        configured_count=$((configured_count + 1))
        attempted=$((attempted + 1))
    fi
    if attempt_notification_provider "Slack" "$(bool_string "$slack_configured")" "2" "$full_message" send_slack_notification; then
        delivered=$((delivered + 1))
    fi

    delivery_channels="$(list_successful_notification_providers)"
    if [[ "$delivered" -gt 0 ]]; then
        NOTIFY_LAST_STATUS="success"
        NOTIFY_LAST_DETAIL="${delivery_channels:-Delivered}"
        log "Notification delivered via ${NOTIFY_LAST_DETAIL}" "INFO"
        return 0
    fi

    if [[ "$attempted" -eq 0 && "$configured_count" -eq 0 ]]; then
        NOTIFY_LAST_DETAIL="No notification channel available"
        log "$NOTIFY_LAST_DETAIL" "WARN"
    else
        NOTIFY_LAST_DETAIL="All notification delivery attempts failed for configured providers: $(list_configured_notification_methods)"
        log "$NOTIFY_LAST_DETAIL" "WARN"
    fi

    NOTIFY_LAST_STATUS="failed"
    return 1
}

# ============ Git 操作 ============
checkpoint() {
    log "📸 Creating checkpoint..." "INFO"
    git add -A 2>/dev/null || true
    git commit -m "🤖 auto-checkpoint: iteration $ITERATION [$(get_progress)]" --no-verify 2>/dev/null || true
}

ensure_branch() {
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if is_protected_branch "$current_branch"; then
        log "⚠️  Currently on $current_branch branch, creating auto branch..." "WARN"
        git checkout -b "auto/$TASK_BRANCH_SLUG-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    fi
}

# ============ 進度追蹤 ============
get_progress() {
    if [[ -f "$TASK_FILE" ]]; then
        local counts
        local done
        local total
        counts="$(get_task_counts "$TASK_FILE")"
        IFS='|' read -r done total _pending _pct <<< "$counts"
        echo "$done/$total"
    else
        echo "0/0"
    fi
}

count_configured_notification_methods() {
    local count=0
    [[ -n "${DISCORD_WEBHOOK:-}" ]] && count=$((count + 1))
    [[ -n "${NTFY_TOPIC:-}" ]] && count=$((count + 1))
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] && count=$((count + 1))
    [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" && -n "${LINE_USER_ID:-}" ]] && count=$((count + 1))
    [[ -n "${SLACK_WEBHOOK:-}" ]] && count=$((count + 1))
    printf '%s' "$count"
}

list_configured_notification_methods() {
    local methods=()
    [[ -n "${DISCORD_WEBHOOK:-}" ]] && methods+=("Discord")
    [[ -n "${NTFY_TOPIC:-}" ]] && methods+=("ntfy")
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] && methods+=("Telegram")
    [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" && -n "${LINE_USER_ID:-}" ]] && methods+=("LINE")
    [[ -n "${SLACK_WEBHOOK:-}" ]] && methods+=("Slack")

    if [[ ${#methods[@]} -eq 0 ]]; then
        printf 'none'
    else
        join_with_commas "${methods[@]}"
    fi
}

doctor_check() {
    local label="$1"
    local status="$2"
    local detail="$3"
    local color="$NC"
    local icon="•"

    case "$status" in
        PASS)
            color="$GREEN"
            icon="✅"
            ;;
        WARN)
            color="$YELLOW"
            icon="⚠️"
            ;;
        FAIL)
            color="$RED"
            icon="❌"
            ;;
    esac

    printf '%b%s%b %-18s %s\n' "$color" "$icon" "$NC" "$label" "$detail"
}

run_doctor() {
    local issues=0
    local warnings=0
    local has_git_repo="false"
    local current_branch=""
    local configured_notifications
    local is_macos="false"
    local repair_lines=""

    [[ "$(uname)" == "Darwin" ]] && is_macos="true"

    echo ""
    echo -e "${CYAN}🩺 Hans Sleep YOLO Mode Doctor${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if command -v claude &>/dev/null; then
        doctor_check "Claude CLI" "PASS" "$(claude --version 2>/dev/null | head -1)"
    else
        doctor_check "Claude CLI" "FAIL" "Not installed. Run: npm install -g @anthropic-ai/claude-code"
        issues=$((issues + 1))
    fi

    if git rev-parse --git-dir &>/dev/null; then
        has_git_repo="true"
        current_branch=$(git branch --show-current 2>/dev/null || echo "")
        doctor_check "Git repo" "PASS" "Repository detected${current_branch:+ on branch $current_branch}"
    else
        doctor_check "Git repo" "FAIL" "Not a git repository"
        issues=$((issues + 1))
    fi

    if [[ -n "$current_branch" ]] && is_protected_branch "$current_branch"; then
        doctor_check "Safe branch" "WARN" "Currently on $current_branch. Create a feature branch before overnight runs."
        warnings=$((warnings + 1))
    else
        if [[ -n "$current_branch" ]]; then
            doctor_check "Safe branch" "PASS" "Using $current_branch"
        else
            doctor_check "Safe branch" "PASS" "Not on main/master"
        fi
    fi

    if [[ -f "$ENV_FILE" ]]; then
        doctor_check "Env file" "PASS" "$ENV_FILE found"
    else
        doctor_check "Env file" "WARN" "$ENV_FILE not found. Run ./setup-wizard.sh to create it."
        warnings=$((warnings + 1))
    fi

    configured_notifications="$(list_configured_notification_methods)"
    if [[ "$(count_configured_notification_methods)" -gt 0 ]]; then
        doctor_check "Notifications" "PASS" "Configured: $configured_notifications"
    elif [[ "$is_macos" == "true" ]]; then
        doctor_check "Notifications" "WARN" "No phone channel configured. macOS local notifications only."
        warnings=$((warnings + 1))
    else
        doctor_check "Notifications" "WARN" "None configured. Run ./sleep-safe-runner.sh --notify-test after setup."
        warnings=$((warnings + 1))
    fi

    if [[ -n "$(get_timeout_bin)" ]]; then
        doctor_check "Session timeout" "PASS" "Using $(get_timeout_bin)"
    else
        doctor_check "Session timeout" "WARN" "timeout/gtimeout missing. Sessions can hang indefinitely."
        warnings=$((warnings + 1))
    fi

    if all_core_files_present; then
        doctor_check "Installed files" "PASS" "Core files present"
    else
        doctor_check "Installed files" "WARN" "Missing core files: $(list_missing_core_files). Hans Sleep YOLO Mode may not function correctly. Run install.sh to restore them."
        warnings=$((warnings + 1))
    fi

    if [[ "$has_git_repo" == "true" ]]; then
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            doctor_check "Working tree" "WARN" "Uncommitted changes detected"
            warnings=$((warnings + 1))
        else
            doctor_check "Working tree" "PASS" "Clean"
        fi
    fi

    repair_lines="$(collect_repair_hints "$TASK_NAME" "$TASK_FILE" "$PROGRESS_FILE")"
    echo ""
    if [[ -n "$repair_lines" ]]; then
        echo "🛠 Suggested repairs:"
        printf '%s\n' "$repair_lines" | sed 's/^/   /'
        echo ""
    fi

    if [[ "$issues" -eq 0 ]]; then
        echo -e "${GREEN}Ready for sleep mode: YES${NC}"
        [[ "$warnings" -gt 0 ]] && echo -e "${YELLOW}Warnings: $warnings${NC}"
        exit 0
    fi

    echo -e "${RED}Ready for sleep mode: NO${NC}"
    echo -e "${RED}Issues: $issues${NC}"
    [[ "$warnings" -gt 0 ]] && echo -e "${YELLOW}Warnings: $warnings${NC}"
    exit 1
}

run_notify_test() {
    local configured_count
    local is_macos="false"

    [[ "$(uname)" == "Darwin" ]] && is_macos="true"
    if [[ -z "$NOTIFY_TEST_MESSAGE" ]]; then
        NOTIFY_TEST_MESSAGE="Hans Sleep YOLO Mode test notification ($(date '+%Y-%m-%d %H:%M:%S'))"
    fi
    configured_count="$(count_configured_notification_methods)"

    if [[ "$configured_count" -eq 0 && "$is_macos" != "true" ]]; then
        echo "❌ No notification channel configured. Run ./setup-wizard.sh or create .sleep-yolo.env from .sleep-yolo.env.example and configure your notification providers first." >&2
        exit 1
    fi

    if notify "$NOTIFY_TEST_MESSAGE" "🧪"; then
        echo "✅ Test notification triggered via: $NOTIFY_LAST_DETAIL"
        if [[ "$configured_count" -eq 0 && "$is_macos" == "true" ]]; then
            echo "ℹ️ Delivered via macOS system notification only."
        fi
        print_notification_health_report
    else
        echo "❌ Notification test failed: ${NOTIFY_LAST_DETAIL:-}" >&2
        print_notification_health_report >&2
        exit 1
    fi
}

run_repair() {
    local repaired=0
    local branch_hint=""
    local timestamp

    mkdir -p "$(dirname "$TASK_FILE")" "$LOG_DIR"
    timestamp="$(iso_timestamp)"

    if [[ ! -f "$TASK_FILE" ]]; then
        write_preset_task_list "$TASK_PRESET" "$TASK_FILE" "$TASK_NAME" "$TASK_DESCRIPTION"
        repaired=$((repaired + 1))
    fi

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        cat > "$PROGRESS_FILE" << EOF
# Progress

- Repaired task metadata for $TASK_NAME on $timestamp
- Review task_list.md and continue from the next unfinished step
EOF
        repaired=$((repaired + 1))
    fi

    if [[ ! -f "$METADATA_FILE" ]]; then
        write_task_metadata_file "$TASK_NAME" "$TASK_DESCRIPTION" "$TASK_PRESET" "$METADATA_FILE" "$timestamp" "$timestamp"
        repaired=$((repaired + 1))
    fi

    record_task_status "repaired" "true"

    echo ""
    echo -e "${CYAN}🛠 Repair result: $TASK_NAME${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ "$repaired" -gt 0 ]]; then
        echo "✅ Recreated $repaired missing task artifact(s)."
    else
        echo "ℹ️ No files were missing; status artifact refreshed."
    fi

    if git rev-parse --git-dir &>/dev/null; then
        current_branch=$(git branch --show-current 2>/dev/null || echo "")
        if [[ -n "$current_branch" ]] && is_protected_branch "$current_branch"; then
            branch_hint="git checkout -b auto/$(to_branch_slug "$TASK_NAME")"
            echo "⚠️ Safe branch required: $branch_hint"
        fi
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            echo "⚠️ Working tree is dirty; commit or stash before overnight runs."
        fi
    fi

    if ! all_core_files_present; then
        echo "⚠️ Missing core files: $(list_missing_core_files)"
        echo "   Run install.sh to restore them."
    fi

    echo "📄 Status artifact: $STATUS_FILE"
    echo "🕘 History artifact: $HISTORY_FILE"
}

check_completion() {
    if [[ -f "$TASK_FILE" ]]; then
        local counts
        local done
        local total
        counts="$(get_task_counts "$TASK_FILE")"
        IFS='|' read -r done total _pending _pct <<< "$counts"
        [[ "$total" -gt 0 && "$done" -eq "$total" ]]
    else
        return 1
    fi
}

# ============ 清理函數 ============
cleanup() {
    local end_time elapsed
    local failure_signal
    local failure_parts
    local _category
    local _summary
    local hint
    end_time=$(date +%s)
    elapsed=$(( (end_time - START_TIME) / 60 ))

    log "🛑 Runner stopping..." "WARN"
    record_task_status "stopped" "true"
    checkpoint
    failure_signal="$(get_recent_failure_signal "$LOG_DIR")"
    failure_parts="$(get_failure_details "$failure_signal")"
    IFS='|' read -r _category _summary hint <<< "$failure_parts"
    if ! notify "Runner stopped after $ITERATION iterations (${elapsed}m). Progress: $(get_progress)${hint:+. $hint}" "🛑"; then
        log "Cleanup notification failed: ${NOTIFY_LAST_DETAIL:-unknown notification failure}" "WARN"
    fi

    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP
trap cleanup_temp_dir EXIT

# ============ 前置檢查 ============
preflight_check() {
    log "🔍 Running preflight checks..." "INFO"
    record_task_status "preflight" "false"

    # 檢查 Claude CLI
    if ! command -v claude &> /dev/null; then
        log "❌ Claude CLI not found." "ERROR"
        log "   Install: npm install -g @anthropic-ai/claude-code" "ERROR"
        record_task_status "preflight_failed" "true"
        exit 1
    fi

    # 檢查 Git
    if ! git rev-parse --git-dir &> /dev/null; then
        log "❌ Not a git repository. Run: git init" "ERROR"
        record_task_status "preflight_failed" "true"
        exit 1
    fi

    # 確保不在 main/master
    ensure_branch

    TIMEOUT_BIN="$(get_timeout_bin)"
    if [[ -z "$TIMEOUT_BIN" ]]; then
        log "⚠️  Neither timeout nor gtimeout is installed. Sessions will run without a per-session timeout." "WARN"
    fi

    # 通知設定提醒（非阻斷，Mac 使用者有系統通知作為 fallback）
    local has_phone_notify=false
    [[ -n "${DISCORD_WEBHOOK:-}" ]] && has_phone_notify=true
    [[ -n "${NTFY_TOPIC:-}" ]] && has_phone_notify=true
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && has_phone_notify=true
    [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" ]] && has_phone_notify=true
    [[ -n "${SLACK_WEBHOOK:-}" ]] && has_phone_notify=true

    if [[ "$has_phone_notify" == "false" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            log "ℹ️  No phone notification configured. macOS system notifications will be used." "INFO"
        else
            log "⚠️  No notification method configured. You won't receive updates on your phone." "WARN"
            log "   Run ./setup-wizard.sh or edit $ENV_FILE to configure notifications." "WARN"
            echo ""
            read -p "繼續執行嗎？[y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    log "✅ Preflight checks passed" "SUCCESS"
    record_task_status "preflight_passed" "true"
}

# ============ 初始化任務 ============
init_task() {
    if [[ ! -f "$TASK_FILE" ]]; then
        log "📝 Initializing task: $TASK_NAME" "INFO"
        record_task_status "initializing" "false"

        # 組合任務描述 prompt
        local description_part=""
        if [[ -n "${TASK_DESCRIPTION:-}" ]]; then
            description_part="

Task description: $TASK_DESCRIPTION"
        fi
        local preset_part=""
        local init_timestamp
        init_timestamp="$(iso_timestamp)"
        if [[ "$TASK_PRESET" != "custom" ]]; then
            preset_part="

$(get_preset_init_context "$TASK_PRESET")"
        fi
        write_task_metadata_file "$TASK_NAME" "$TASK_DESCRIPTION" "$TASK_PRESET" "$METADATA_FILE" "$init_timestamp" "$init_timestamp"

        # 讓 Claude 初始化任務，並 fallback 到手動建立
        if ! claude -p \
            "Initialize autonomous task '$TASK_NAME'.$description_part$preset_part

Create the file .autonomous/$TASK_NAME/task_list.md with a detailed breakdown of what needs to be done.

Format (use EXACTLY this checkbox format):
- [ ] Step 1: ...
- [ ] Step 2: ...

Requirements:
- Break into 10-30 small, specific, actionable steps
- Each step should be completable in 5-15 minutes
- Include setup steps, implementation, and testing
- Also create .autonomous/$TASK_NAME/progress.md with a brief task summary
- Read and respect .autonomous/$TASK_NAME/task-metadata.json when planning the task list" \
            --dangerously-skip-permissions \
            --max-turns 20 \
            > "$LOG_DIR/init.log" 2>&1; then
            log "⚠️  Claude init returned non-zero, checking if file was created..." "WARN"
        fi

        if [[ -f "$TASK_FILE" ]]; then
            local task_counts
            local task_count
            task_counts="$(get_task_counts "$TASK_FILE")"
            IFS='|' read -r _done task_count _pending _pct <<< "$task_counts"
            log "✅ Task initialized with $task_count tasks" "SUCCESS"
        else
            log "❌ Failed to create task list. Creating a minimal one..." "ERROR"
            mkdir -p ".autonomous/$TASK_NAME"
            write_preset_task_list "$TASK_PRESET" "$TASK_FILE" "$TASK_NAME" "$TASK_DESCRIPTION"
            cat > "$PROGRESS_FILE" <<EOF
# Progress

- Initialized fallback task list for $TASK_NAME
- Continue with the preset skeleton and refine as work progresses
EOF
            log "✅ Created minimal task list. Claude will fill in details." "SUCCESS"
        fi
        record_task_status "initialized" "true"
    else
        if [[ ! -f "$METADATA_FILE" ]]; then
            write_task_metadata_file "$TASK_NAME" "$TASK_DESCRIPTION" "$TASK_PRESET" "$METADATA_FILE" "$(iso_timestamp)" "$(iso_timestamp)"
        fi
        log "📋 Resuming existing task: $(get_progress) completed" "INFO"
        record_task_status "resumed" "true"
    fi
}

# ============ 主循環 ============
main() {
    # Banner（固定寬度，截斷長名字）
    local display_name="${TASK_NAME:0:40}"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     🌙 Sleep-Safe Autonomous Runner v3.1             ║${NC}"
    printf "${GREEN}║     Task: ${CYAN}%-44s${GREEN}║${NC}\n" "$display_name"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    record_task_status "starting" "true"
    preflight_check
    init_task

    log "🚀 Starting autonomous runner" "SUCCESS"
    record_task_status "running" "true"
    notify "Started. Progress: $(get_progress)" "🚀" || true

    while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
        ITERATION=$((ITERATION + 1))

        echo ""
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "INFO"
        log "📍 Iteration $ITERATION / $MAX_ITERATIONS | Progress: $(get_progress)" "INFO"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "INFO"

        SESSION_LOG="$LOG_DIR/session_$(printf '%03d' $ITERATION).log"
        record_task_status "session_running" "false"

        # 執行 Claude
        EXIT_CODE=0
        if [[ -n "$TIMEOUT_BIN" ]]; then
            "$TIMEOUT_BIN" "${MAX_SESSION_MINUTES}m" claude -p \
                "You are continuing autonomous task '$TASK_NAME'.
${TASK_DESCRIPTION:+Task context: $TASK_DESCRIPTION

}INSTRUCTIONS:
1. Read .autonomous/$TASK_NAME/task_list.md
2. Find the FIRST uncompleted task (marked with - [ ])
3. Complete that task fully
4. Mark it done: change - [ ] to - [x]
5. Update .autonomous/$TASK_NAME/progress.md with what you did
6. If blocked, document why in progress.md and move to next task

RULES:
- Complete 1-3 tasks per session (don't rush, do each one properly)
- Never ask questions — make decisions
- Fix errors without asking
- Test your work before marking done
- Commit with descriptive messages after each task

Current progress: $(get_progress)" \
                --dangerously-skip-permissions \
                --max-turns "$MAX_TURNS" \
                > "$SESSION_LOG" 2>&1 || EXIT_CODE=$?
        else
            claude -p \
                "You are continuing autonomous task '$TASK_NAME'.
${TASK_DESCRIPTION:+Task context: $TASK_DESCRIPTION

}INSTRUCTIONS:
1. Read .autonomous/$TASK_NAME/task_list.md
2. Find the FIRST uncompleted task (marked with - [ ])
3. Complete that task fully
4. Mark it done: change - [ ] to - [x]
5. Update .autonomous/$TASK_NAME/progress.md with what you did
6. If blocked, document why in progress.md and move to next task

RULES:
- Complete 1-3 tasks per session (don't rush, do each one properly)
- Never ask questions — make decisions
- Fix errors without asking
- Test your work before marking done
- Commit with descriptive messages after each task

Current progress: $(get_progress)" \
                --dangerously-skip-permissions \
                --max-turns "$MAX_TURNS" \
                > "$SESSION_LOG" 2>&1 || EXIT_CODE=$?
        fi

        if [[ $EXIT_CODE -eq 0 ]]; then
            FAILURE_COUNT=0
            log "✅ Session completed successfully" "SUCCESS"
            record_task_status "session_succeeded" "true"
        elif [[ $EXIT_CODE -eq 124 ]]; then
            # Timeout = Claude was working on a big task, not a failure
            log "⏰ Session timed out (${MAX_SESSION_MINUTES}m) — continuing" "WARN"
            record_task_status "session_timed_out" "true"
        else
            log "❌ Session failed (exit code: $EXIT_CODE)" "ERROR"
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            record_task_status "session_failed" "true"
        fi

        # 檢查連續失敗
        if [[ $FAILURE_COUNT -ge $MAX_CONSECUTIVE_FAILURES ]]; then
            local failure_signal
            local failure_parts
            local _category
            local _summary
            local hint
            log "🔴 Too many consecutive failures ($FAILURE_COUNT). Stopping." "ERROR"
            record_task_status "failed" "true"
            failure_signal="$(get_recent_failure_signal "$LOG_DIR")"
            failure_parts="$(get_failure_details "$failure_signal")"
            IFS='|' read -r _category _summary hint <<< "$failure_parts"
            notify "Stopped: $MAX_CONSECUTIVE_FAILURES consecutive failures. Progress: $(get_progress). Check logs: $LOG_DIR${hint:+. $hint}" "🔴" || true
            checkpoint
            break
        fi

        # 檢查完成
        if check_completion; then
            local elapsed=$(( ($(date +%s) - START_TIME) / 60 ))
            log "🎉 All tasks completed!" "SUCCESS"
            record_task_status "completed" "true"
            notify "All tasks completed! 🎉 Duration: ${elapsed}m, Iterations: $ITERATION" "🎉" || true
            checkpoint
            break
        fi

        # 定期 checkpoint
        if [[ $((ITERATION % CHECKPOINT_EVERY)) -eq 0 ]]; then
            checkpoint
            record_task_status "checkpoint" "true"
            notify "Checkpoint #$ITERATION. Progress: $(get_progress)" "📊" || true
        fi

        log "💤 Sleeping ${SLEEP_BETWEEN_SESSIONS}s..." "INFO"
        record_task_status "sleeping" "false"
        sleep "$SLEEP_BETWEEN_SESSIONS"
    done

    # 最終報告
    checkpoint
    local elapsed=$(( ($(date +%s) - START_TIME) / 60 ))
    log "🏁 Runner finished. Iterations: $ITERATION, Duration: ${elapsed}m, Progress: $(get_progress)" "SUCCESS"
    record_task_status "finished" "true"
    notify "Runner finished. Duration: ${elapsed}m, Progress: $(get_progress)" "🏁" || true
}

# ============ 執行 ============
case "$COMMAND" in
    --doctor)
        run_doctor
        ;;
    --notify-test)
        run_notify_test
        ;;
    --repair)
        run_repair
        ;;
    *)
        main "$@"
        ;;
esac
