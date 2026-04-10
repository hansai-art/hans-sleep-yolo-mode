#!/bin/bash
# ============================================
# 🌙 Sleep-Safe Autonomous Runner v3.1
# 全自動執行，可以安心睡覺
# ============================================
#
# 用法：
#   ./sleep-safe-runner.sh "任務名稱" "任務詳細說明（可選）"
#   ./sleep-safe-runner.sh --status "任務名稱"    # 查看進度
#   ./sleep-safe-runner.sh --list                 # 列出所有任務
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

# ============ 狀態查看模式 ============
if [[ "${1:-}" == "--status" ]]; then
    TASK="${2:-my-task}"
    if ! validate_task_name "$TASK"; then
        echo "❌ Invalid task name: $TASK" >&2
        exit 1
    fi
    TASK_FILE=".autonomous/$TASK/task_list.md"
    LOG_DIR=".autonomous/$TASK/logs"
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

    echo ""
    echo -e "${CYAN}📊 Status: $TASK${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ -f "$TASK_FILE" ]]; then
        TOTAL=$(grep -c '^\s*- \[' "$TASK_FILE" 2>/dev/null || echo "0")
        DONE=$(grep -c '^\s*- \[x\]' "$TASK_FILE" 2>/dev/null || echo "0")
        PENDING=$(( TOTAL - DONE ))
        PCT=$(( TOTAL > 0 ? DONE * 100 / TOTAL : 0 ))

        echo -e "Progress: ${GREEN}$DONE${NC}/$TOTAL tasks (${PCT}%)"
        echo ""

        if [[ $DONE -gt 0 ]]; then
            echo -e "${GREEN}✅ Recently completed:${NC}"
            grep '^\s*- \[x\]' "$TASK_FILE" | tail -5 | sed 's/^\s*- \[x\] /   ✓ /'
            echo ""
        fi

        if [[ $PENDING -gt 0 ]]; then
            echo -e "${YELLOW}⏳ Next up:${NC}"
            grep '^\s*- \[ \]' "$TASK_FILE" | head -5 | sed 's/^\s*- \[ \] /   • /'
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

    if [[ -f "$LOG_DIR/runner.log" ]]; then
        echo "📋 Recent log (last 6 lines):"
        tail -6 "$LOG_DIR/runner.log" | sed 's/^/   /'
        echo ""
    fi

    echo "📁 Recent checkpoints:"
    git log --oneline -5 --format="   %h %s" 2>/dev/null | grep -F -e "checkpoint" -e "$TASK" || echo "   (none yet)"
    echo ""
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
TASK_NAME="${1:-my-task}"
TASK_DESCRIPTION="${2:-}"            # 任務詳細描述（可選，給 Claude 更多 context）
ENV_FILE=".sleep-yolo.env"
TIMEOUT_BIN=""
TASK_BRANCH_SLUG=""

if ! validate_task_name "$TASK_NAME"; then
    echo "❌ Invalid task name. Avoid leading -, /, \\, newline, and reserved names like . or .." >&2
    exit 1
fi

TASK_BRANCH_SLUG="$(to_branch_slug "$TASK_NAME")"

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
    full_message_json=$(json_escape "$full_message")
    line_user_id_json=$(json_escape "${LINE_USER_ID:-}")
    apple_message=$(apple_escape "$message")
    apple_task_name=$(apple_escape "$TASK_NAME")

    log "📢 Notification: $message" "INFO"

    # macOS 系統通知（零設定，在電腦螢幕上顯示）
    if [[ "$(uname)" == "Darwin" ]]; then
        osascript -e "display notification \"$apple_message\" with title \"Claude Code 🤖\" subtitle \"[$apple_task_name]\"" 2>/dev/null || true
    fi

    # Linux 系統通知（如果有安裝 libnotify）
    if [[ "$(uname)" == "Linux" ]] && command -v notify-send &>/dev/null; then
        notify-send "Claude Code 🤖 [$TASK_NAME]" "$message" 2>/dev/null || true
    fi

    # Discord（已有 Discord 的話最快）
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        curl -s -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\":\"$full_message_json\"}" \
            > /dev/null 2>&1 || log "Discord notification failed" "WARN"
    fi

    # ntfy.sh
    if [[ -n "${NTFY_TOPIC:-}" ]]; then
        curl -s -X POST "https://ntfy.sh/$NTFY_TOPIC" \
            -H "Title: Claude Code 🤖" \
            -H "Priority: default" \
            -d "$full_message" \
            > /dev/null 2>&1 || log "ntfy notification failed" "WARN"
    fi

    # Telegram
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
            --data-urlencode "text=$full_message" \
            > /dev/null 2>&1 || log "Telegram notification failed" "WARN"
    fi

    # LINE Messaging API
    if [[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" && -n "${LINE_USER_ID:-}" ]]; then
        curl -s -X POST "https://api.line.me/v2/bot/message/push" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
            -d "{\"to\":\"$line_user_id_json\",\"messages\":[{\"type\":\"text\",\"text\":\"$full_message_json\"}]}" \
            > /dev/null 2>&1 || log "LINE notification failed" "WARN"
    fi

    # Slack
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$full_message_json\"}" \
            > /dev/null 2>&1 || log "Slack notification failed" "WARN"
    fi
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
    if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
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
    notify "Runner stopped after $ITERATION iterations (${elapsed}m). Progress: $(get_progress)" "🛑"

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
    notify "Started. Progress: $(get_progress)" "🚀"

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
            notify "Stopped: $MAX_CONSECUTIVE_FAILURES consecutive failures. Progress: $(get_progress). Check logs: $LOG_DIR" "🔴"
            checkpoint
            break
        fi

        # 檢查完成
        if check_completion; then
            local elapsed=$(( ($(date +%s) - START_TIME) / 60 ))
            log "🎉 All tasks completed!" "SUCCESS"
            notify "All tasks completed! 🎉 Duration: ${elapsed}m, Iterations: $ITERATION" "🎉"
            checkpoint
            break
        fi

        # 定期 checkpoint
        if [[ $((ITERATION % CHECKPOINT_EVERY)) -eq 0 ]]; then
            checkpoint
            notify "Checkpoint #$ITERATION. Progress: $(get_progress)" "📊"
        fi

        log "💤 Sleeping ${SLEEP_BETWEEN_SESSIONS}s..." "INFO"
        sleep "$SLEEP_BETWEEN_SESSIONS"
    done

    # 最終報告
    checkpoint
    local elapsed=$(( ($(date +%s) - START_TIME) / 60 ))
    log "🏁 Runner finished. Iterations: $ITERATION, Duration: ${elapsed}m, Progress: $(get_progress)" "SUCCESS"
    notify "Runner finished. Duration: ${elapsed}m, Progress: $(get_progress)" "🏁"
}

# ============ 執行 ============
main "$@"
