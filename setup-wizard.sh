#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ENV_FILE=".sleep-yolo.env"
EXAMPLE_FILE=".sleep-yolo.env.example"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🧙 Hans Sleep YOLO Mode Setup Wizard   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""

if [[ ! -f "$EXAMPLE_FILE" ]]; then
    echo -e "${YELLOW}⚠️  找不到 $EXAMPLE_FILE，請確認你在已安裝 YOLO Mode 的專案目錄。${NC}"
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    cp "$EXAMPLE_FILE" "$ENV_FILE"
    echo -e "${BLUE}📄 已建立 $ENV_FILE${NC}"
else
    echo -e "${BLUE}📄 將使用既有的 $ENV_FILE${NC}"
fi

set_env_value() {
    local key="$1"
    local value="$2"
    local escaped_value="${value//\\/\\\\}"
    escaped_value="${escaped_value//&/\\&}"
    escaped_value="${escaped_value//|/\\|}"

    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|^${key}=.*|${key}=${escaped_value}|" "$ENV_FILE"
    else
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$ENV_FILE"
    fi
}

set_numeric_value_if_provided() {
    local key="$1"
    local value="$2"

    [[ -z "$value" ]] && return 0

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        set_env_value "$key" "$value"
    else
        echo -e "${YELLOW}⚠️  $key 需為數字，保留原本設定值。${NC}"
    fi
}

echo ""
echo -e "${CYAN}通知方式（選一個你已經在用的即可）${NC}"
echo "1) Discord webhook"
echo "2) ntfy.sh"
echo "3) Telegram bot"
echo "4) Slack webhook"
echo "5) 先略過"
echo ""
read -p "選擇 [1/2/3/4/5，預設 5]: " NOTIFY_CHOICE
NOTIFY_CHOICE="${NOTIFY_CHOICE:-5}"

case "$NOTIFY_CHOICE" in
    1)
        read -p "貼上 Discord Webhook URL: " DISCORD_WEBHOOK
        [[ -n "$DISCORD_WEBHOOK" ]] && set_env_value "DISCORD_WEBHOOK" "$DISCORD_WEBHOOK"
        ;;
    2)
        echo "請先在手機的 ntfy app 裡訂閱一個頻道（例如 my-claude-abc123）"
        read -p "輸入你取的頻道名稱: " NTFY_TOPIC
        [[ -n "$NTFY_TOPIC" ]] && set_env_value "NTFY_TOPIC" "$NTFY_TOPIC"
        ;;
    3)
        read -p "貼上 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        read -p "貼上 Telegram Chat ID: " TELEGRAM_CHAT_ID
        [[ -n "$TELEGRAM_BOT_TOKEN" ]] && set_env_value "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
        [[ -n "$TELEGRAM_CHAT_ID" ]] && set_env_value "TELEGRAM_CHAT_ID" "$TELEGRAM_CHAT_ID"
        ;;
    4)
        read -p "貼上 Slack Webhook URL: " SLACK_WEBHOOK
        [[ -n "$SLACK_WEBHOOK" ]] && set_env_value "SLACK_WEBHOOK" "$SLACK_WEBHOOK"
        ;;
    *)
        echo -e "${YELLOW}⏭️  已略過通知設定，你之後可以再編輯 $ENV_FILE${NC}"
        ;;
esac

echo ""
echo -e "${CYAN}執行參數（直接 Enter 使用預設值）${NC}"
read -p "MAX_ITERATIONS [100]: " MAX_ITERATIONS
read -p "MAX_SESSION_MINUTES [45]: " MAX_SESSION_MINUTES
read -p "CHECKPOINT_EVERY [3]: " CHECKPOINT_EVERY

set_numeric_value_if_provided "MAX_ITERATIONS" "${MAX_ITERATIONS:-}"
set_numeric_value_if_provided "MAX_SESSION_MINUTES" "${MAX_SESSION_MINUTES:-}"
set_numeric_value_if_provided "CHECKPOINT_EVERY" "${CHECKPOINT_EVERY:-}"

echo ""
echo -e "${GREEN}✅ 設定完成${NC}"
echo ""
echo "下一步："
echo "  1. 用編輯器檢查 $ENV_FILE"
echo "  2. 先跑健康檢查：./sleep-safe-runner.sh --doctor"
echo "  3. 測試通知：./sleep-safe-runner.sh --notify-test"
echo "  4. 建立 feature branch：git checkout -b auto/$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"
echo "  5. 用 preset 啟動：./sleep-safe-runner.sh --preset feature \"你的任務名稱\" \"任務描述\""
echo "     其他 preset：bugfix / refactor / docs / repo-setup"
echo "  6. 查看狀態 artifact：.autonomous/你的任務名稱/status.json"
echo "  7. 團隊版可先參考：.sleep-yolo.team.example.json"
echo ""
echo "快捷啟動指令（只需設定一次）："
if [[ "$(uname)" == "Darwin" ]]; then
    echo "  echo 'alias yolo=\"claude --dangerously-skip-permissions\"' >> ~/.zshrc && source ~/.zshrc"
else
    echo "  echo 'alias yolo=\"claude --dangerously-skip-permissions\"' >> ~/.bashrc && source ~/.bashrc"
fi

echo ""
read -p "要現在直接測試通知嗎？[y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./sleep-safe-runner.sh --notify-test
fi
