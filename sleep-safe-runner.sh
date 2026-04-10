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
#   ./sleep-safe-runner.sh --doctor               # 檢查環境與設定
#   ./sleep-safe-runner.sh --notify-test          # 測試通知設定
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
readonly CORE_INSTALL_FILES=(
    "CLAUDE.md"
    "setup-wizard.sh"
    "sleep-safe-runner.sh"
    ".sleep-yolo.env.example"
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

get_task_counts() {
    local task_file="$1"
    local total=0
    local done=0
    local pending=0
    local pct=0

    if [[ -f "$task_file" ]]; then
        total=$(grep -c '^\s*- \[' "$task_file" 2>/dev/null || echo "0")
        done=$(grep -c '^\s*- \[x\]' "$task_file" 2>/dev/null || echo "0")
        pending=$(( total - done ))
        pct=$(( total > 0 ? done * 100 / total : 0 ))
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
    grep '^\s*- \[x\]' "$task_file" | tail -5 | sed 's/^\s*- \[x\] /✓ /'
}

get_next_up_lines() {
    local task_file="$1"
    [[ -f "$task_file" ]] || return 0
    grep '^\s*- \[ \]' "$task_file" | head -5 | sed 's/^\s*- \[ \] /• /'
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
            start=(count > 5 ? count - 4 : 1)
            for (i = start; i <= count; i++) print lines[i]
        }
    ' "$progress_file"
}

get_recent_log_lines() {
    local log_dir="$1"
    [[ -f "$log_dir/runner.log" ]] || return 0
    tail -6 "$log_dir/runner.log"
}

get_recent_failure_signal() {
    local log_dir="$1"
    local runner_log="$log_dir/runner.log"
    [[ -f "$runner_log" ]] || return 0

    tail -100 "$runner_log" | grep -E "$FAILURE_SIGNAL_PATTERN" | tail -1
}

get_recent_checkpoints_lines() {
    local task_name="$1"
    git log --oneline -5 --format="%h %s" 2>/dev/null | grep -F -e "checkpoint" -e "$task_name" || true
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

print_task_status_json() {
    local task_name="$1"
    local task_file="$2"
    local log_dir="$3"
    local progress_file="$4"
    local counts
    local done
    local total
    local pending
    local pct
    local state
    local failure_signal
    local summary_json
    local completed_json
    local next_up_json
    local recent_log_json
    local checkpoint_json

    counts="$(get_task_counts "$task_file")"
    IFS='|' read -r done total pending pct <<< "$counts"
    state="$(get_task_state "$task_file")"
    failure_signal="$(get_recent_failure_signal "$log_dir")"
    summary_json="$(get_progress_summary_lines "$progress_file" | json_array_from_stream)"
    completed_json="$(get_recent_completed_lines "$task_file" | json_array_from_stream)"
    next_up_json="$(get_next_up_lines "$task_file" | json_array_from_stream)"
    recent_log_json="$(get_recent_log_lines "$log_dir" | json_array_from_stream)"
    checkpoint_json="$(get_recent_checkpoints_lines "$task_name" | json_array_from_stream)"

    printf '{'
    printf '"task":"%s",' "$(json_escape "$task_name")"
    printf '"state":"%s",' "$(json_escape "$state")"
    printf '"taskFileExists":%s,' "$( [[ -f "$task_file" ]] && printf 'true' || printf 'false' )"
    printf '"progressFileExists":%s,' "$( [[ -f "$progress_file" ]] && printf 'true' || printf 'false' )"
    printf '"progress":{"done":%s,"total":%s,"pending":%s,"percent":%s},' "$done" "$total" "$pending" "$pct"
    printf '"summaryLines":%s,' "$summary_json"
    printf '"recentCompleted":%s,' "$completed_json"
    printf '"nextUp":%s,' "$next_up_json"
    printf '"recentLog":%s,' "$recent_log_json"
    printf '"recentCheckpoints":%s,' "$checkpoint_json"
    printf '"failureSummary":"%s"' "$(json_escape "$failure_signal")"
    printf '}\n'
}

# ============ 狀態查看模式 ============
if [[ "${1:-}" == "--status" ]]; then
    TASK="${2:-my-task}"
    if ! validate_task_name "$TASK"; then
        echo "❌ Invalid task name: $TASK" >&2
        exit 1
    fi
    TASK_FILE=".autonomous/$TASK/task_list.md"
    LOG_DIR=".autonomous/$TASK/logs"
    PROGRESS_FILE="$(task_progress_file_path "$TASK")"
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
    COUNTS="$(get_task_counts "$TASK_FILE")"
    IFS='|' read -r DONE TOTAL PENDING PCT <<< "$COUNTS"
    FAILURE_SIGNAL="$(get_recent_failure_signal "$LOG_DIR")"
    CHECKPOINT_LINES="$(get_recent_checkpoints_lines "$TASK")"

    echo ""
    echo -e "${CYAN}📊 Status: $TASK${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ -f "$TASK_FILE" ]]; then
        echo -e "Progress: ${GREEN}$DONE${NC}/$TOTAL tasks (${PCT}%)"
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
    exit 0
fi

if [[ "${1:-}" == "--status-json" ]]; then
    TASK="${2:-my-task}"
    if ! validate_task_name "$TASK"; then
        echo "❌ Invalid task name: $TASK" >&2
        exit 1
    fi

    TASK_FILE=".autonomous/$TASK/task_list.md"
    LOG_DIR=".autonomous/$TASK/logs"
    PROGRESS_FILE="$(task_progress_file_path "$TASK")"
    print_task_status_json "$TASK" "$TASK_FILE" "$LOG_DIR" "$PROGRESS_FILE"
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
            total=$(grep -c '^\s*- \[' "$task_file" 2>/dev/null || echo "0")
            done=$(grep -c '^\s*- \[x\]' "$task_file" 2>/dev/null || echo "0")
            pct=$(( total > 0 ? done * 100 / total : 0 ))
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
NOTIFY_TEST_MESSAGE=""
ENV_FILE=".sleep-yolo.env"
TIMEOUT_BIN=""
TASK_BRANCH_SLUG=""
TEMP_BASE_DIR="${TMPDIR:-/tmp}/hans-sleep-yolo-mode-$USER-$$"

case "$COMMAND" in
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

if [[ "$COMMAND" == "--doctor" || "$COMMAND" == "--notify-test" ]]; then
    LOG_DIR="$TEMP_BASE_DIR/$TASK_NAME/logs"
    TASK_FILE="$TEMP_BASE_DIR/$TASK_NAME/task_list.md"
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
notify() {
    local message="$1"
    local emoji="${2:-🤖}"
    local full_message="$emoji [$TASK_NAME] $message"
    local full_message_json
    local line_user_id_json
    local apple_message
    local apple_task_name
    local attempted=0
    local delivered=0
    local delivery_channels=()
    full_message_json=$(json_escape "$full_message")
    line_user_id_json=$(json_escape "${LINE_USER_ID:-}")
    apple_message=$(apple_escape "$message")
    apple_task_name=$(apple_escape "$TASK_NAME")

    log "📢 Notification: $message" "INFO"

    # macOS 系統通知（零設定，在電腦螢幕上顯示）
    if [[ "$(uname)" == "Darwin" ]]; then
        attempted=$((attempted + 1))
        if osascript -e "display notification \"$apple_message\" with title \"Claude Code 🤖\" subtitle \"[$apple_task_name]\"" 2>/dev/null; then
            delivered=$((delivered + 1))
            delivery_channels+=("macOS")
        fi
    fi

    # Linux 系統通知（如果有安裝 libnotify）
    if [[ "$(uname)" == "Linux" ]] && command -v notify-send &>/dev/null; then
        attempted=$((attempted + 1))
        if notify-send "Claude Code 🤖 [$TASK_NAME]" "$message" 2>/dev/null; then
            delivered=$((delivered + 1))
            delivery_channels+=("notify-send")
        fi
    fi

    # Discord（已有 Discord 的話最快）
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        attempted=$((attempted + 1))
        if curl -s -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"$full_message_json\"}" \
            > /dev/null 2>&1; then
            delivered=$((delivered + 1))
            delivery_channels+=("Discord")
        else
            log "Discord notification failed" "WARN"
        fi
    fi

    # ntfy.sh
    if [[ -n "${NTFY_TOPIC:-}" ]]; then
        attempted=$((attempted + 1))
        if curl -s -X POST "https://ntfy.sh/$NTFY_TOPIC" \
            -H "Title: Claude Code 🤖" \
            -H "Priority: default" \
            -d "$full_message" \
            > /dev/null 2>&1; then
            delivered=$((delivered + 1))
            delivery_channels+=("ntfy")
        else
            log "ntfy notification failed" "WARN"
        fi
    fi

    # Telegram
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        attempted=$((attempted + 1))
        if curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
            --data-urlencode "text=$full_message" \
            > /dev/null 2>&1; then
            delivered=$((delivered + 1))
            delivery_channels+=("Telegram")
        else
            log "Telegram notification failed" "WARN"
        fi
    fi

    # LINE Messaging API
    if [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" && -n "${LINE_USER_ID:-}" ]]; then
        attempted=$((attempted + 1))
        if curl -s -X POST "https://api.line.me/v2/bot/message/push" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
            -d "{\"to\":\"$line_user_id_json\",\"messages\":[{\"type\":\"text\",\"text\":\"$full_message_json\"}]}" \
            > /dev/null 2>&1; then
            delivered=$((delivered + 1))
            delivery_channels+=("LINE")
        else
            log "LINE notification failed" "WARN"
        fi
    fi

    # Slack
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        attempted=$((attempted + 1))
        if curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$full_message_json\"}" \
            > /dev/null 2>&1; then
            delivered=$((delivered + 1))
            delivery_channels+=("Slack")
        else
            log "Slack notification failed" "WARN"
        fi
    fi

    if [[ "$delivered" -gt 0 ]]; then
        NOTIFY_LAST_STATUS="success"
        NOTIFY_LAST_DETAIL="$(join_with_commas "${delivery_channels[@]}")"
        return 0
    fi

    if [[ "$attempted" -eq 0 ]]; then
        NOTIFY_LAST_DETAIL="No notification channel available"
    else
        NOTIFY_LAST_DETAIL="All notification delivery attempts failed"
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
        local total done
        total=$(grep -c '^\s*- \[' "$TASK_FILE" 2>/dev/null || echo "0")
        done=$(grep -c '^\s*- \[x\]' "$TASK_FILE" 2>/dev/null || echo "0")
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

    echo ""
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
        NOTIFY_TEST_MESSAGE="Hans Sleep YOLO Mode test notification ($(date '+%Y-%m-%d %H:%M:%S'))."
    fi
    configured_count="$(count_configured_notification_methods)"

    if [[ "$configured_count" -eq 0 && "$is_macos" != "true" ]]; then
        echo "❌ No notification channel configured. Run ./setup-wizard.sh or create .sleep-yolo.env from .sleep-yolo.env.example first." >&2
        exit 1
    fi

    if notify "$NOTIFY_TEST_MESSAGE" "🧪"; then
        echo "✅ Test notification triggered via: $NOTIFY_LAST_DETAIL"
        if [[ "$configured_count" -eq 0 && "$is_macos" == "true" ]]; then
            echo "ℹ️ Delivered via macOS system notification only."
        fi
    else
        echo "❌ Notification test failed: $NOTIFY_LAST_DETAIL" >&2
        exit 1
    fi
}

check_completion() {
    if [[ -f "$TASK_FILE" ]]; then
        local total done
        total=$(grep -c '^\s*- \[' "$TASK_FILE" 2>/dev/null || echo "0")
        done=$(grep -c '^\s*- \[x\]' "$TASK_FILE" 2>/dev/null || echo "0")
        [[ "$total" -gt 0 && "$done" -eq "$total" ]]
    else
        return 1
    fi
}

# ============ 清理函數 ============
cleanup() {
    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$(( (end_time - START_TIME) / 60 ))

    log "🛑 Runner stopping..." "WARN"
    checkpoint
    notify "Runner stopped after $ITERATION iterations (${elapsed}m). Progress: $(get_progress)" "🛑" || true

    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP

# ============ 前置檢查 ============
preflight_check() {
    log "🔍 Running preflight checks..." "INFO"

    # 檢查 Claude CLI
    if ! command -v claude &> /dev/null; then
        log "❌ Claude CLI not found." "ERROR"
        log "   Install: npm install -g @anthropic-ai/claude-code" "ERROR"
        exit 1
    fi

    # 檢查 Git
    if ! git rev-parse --git-dir &> /dev/null; then
        log "❌ Not a git repository. Run: git init" "ERROR"
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
}

# ============ 初始化任務 ============
init_task() {
    if [[ ! -f "$TASK_FILE" ]]; then
        log "📝 Initializing task: $TASK_NAME" "INFO"

        # 組合任務描述 prompt
        local description_part=""
        if [[ -n "${TASK_DESCRIPTION:-}" ]]; then
            description_part="

Task description: $TASK_DESCRIPTION"
        fi

        # 讓 Claude 初始化任務，並 fallback 到手動建立
        if ! claude -p \
            "Initialize autonomous task '$TASK_NAME'.$description_part

Create the file .autonomous/$TASK_NAME/task_list.md with a detailed breakdown of what needs to be done.

Format (use EXACTLY this checkbox format):
- [ ] Step 1: ...
- [ ] Step 2: ...

Requirements:
- Break into 10-30 small, specific, actionable steps
- Each step should be completable in 5-15 minutes
- Include setup steps, implementation, and testing
- Also create .autonomous/$TASK_NAME/progress.md with a brief task summary" \
            --dangerously-skip-permissions \
            --max-turns 20 \
            > "$LOG_DIR/init.log" 2>&1; then
            log "⚠️  Claude init returned non-zero, checking if file was created..." "WARN"
        fi

        if [[ -f "$TASK_FILE" ]]; then
            local task_count
            task_count=$(grep -c '^\s*- \[' "$TASK_FILE" 2>/dev/null || echo 0)
            log "✅ Task initialized with $task_count tasks" "SUCCESS"
        else
            log "❌ Failed to create task list. Creating a minimal one..." "ERROR"
            mkdir -p ".autonomous/$TASK_NAME"
            cat > "$TASK_FILE" << EOF
# Task: $TASK_NAME
${TASK_DESCRIPTION:+Description: $TASK_DESCRIPTION}

- [ ] Analyze the codebase and understand current structure
- [ ] Plan implementation approach
- [ ] Implement the feature
- [ ] Write tests
- [ ] Verify tests pass
- [ ] Clean up and finalize
EOF
            log "✅ Created minimal task list. Claude will fill in details." "SUCCESS"
        fi
    else
        log "📋 Resuming existing task: $(get_progress) completed" "INFO"
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

    preflight_check
    init_task

    log "🚀 Starting autonomous runner" "SUCCESS"
    notify "Started. Progress: $(get_progress)" "🚀" || true

    while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
        ITERATION=$((ITERATION + 1))

        echo ""
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "INFO"
        log "📍 Iteration $ITERATION / $MAX_ITERATIONS | Progress: $(get_progress)" "INFO"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "INFO"

        SESSION_LOG="$LOG_DIR/session_$(printf '%03d' $ITERATION).log"

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
        elif [[ $EXIT_CODE -eq 124 ]]; then
            # Timeout = Claude was working on a big task, not a failure
            log "⏰ Session timed out (${MAX_SESSION_MINUTES}m) — continuing" "WARN"
        else
            log "❌ Session failed (exit code: $EXIT_CODE)" "ERROR"
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
        fi

        # 檢查連續失敗
        if [[ $FAILURE_COUNT -ge $MAX_CONSECUTIVE_FAILURES ]]; then
            log "🔴 Too many consecutive failures ($FAILURE_COUNT). Stopping." "ERROR"
            notify "Stopped: $MAX_CONSECUTIVE_FAILURES consecutive failures. Progress: $(get_progress). Check logs: $LOG_DIR" "🔴" || true
            checkpoint
            break
        fi

        # 檢查完成
        if check_completion; then
            local elapsed=$(( ($(date +%s) - START_TIME) / 60 ))
            log "🎉 All tasks completed!" "SUCCESS"
            notify "All tasks completed! 🎉 Duration: ${elapsed}m, Iterations: $ITERATION" "🎉" || true
            checkpoint
            break
        fi

        # 定期 checkpoint
        if [[ $((ITERATION % CHECKPOINT_EVERY)) -eq 0 ]]; then
            checkpoint
            notify "Checkpoint #$ITERATION. Progress: $(get_progress)" "📊" || true
        fi

        log "💤 Sleeping ${SLEEP_BETWEEN_SESSIONS}s..." "INFO"
        sleep "$SLEEP_BETWEEN_SESSIONS"
    done

    # 最終報告
    checkpoint
    local elapsed=$(( ($(date +%s) - START_TIME) / 60 ))
    log "🏁 Runner finished. Iterations: $ITERATION, Duration: ${elapsed}m, Progress: $(get_progress)" "SUCCESS"
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
    *)
        main "$@"
        ;;
esac
