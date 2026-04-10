#!/bin/bash
# ============================================
# 🚀 Hans Sleep YOLO Mode - 一鍵安裝腳本
# ============================================

set -e

# 顏色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🚀 Hans Sleep YOLO Mode 安裝程式       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""

# 取得腳本所在目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_DIR="$(pwd)"

# 檢查是否在正確目錄
if [ "$SCRIPT_DIR" = "$CURRENT_DIR" ]; then
    echo -e "${RED}❌ 請在你的專案目錄執行此腳本${NC}"
    echo ""
    echo "使用方式："
    echo "  cd ~/Projects/你的專案"
    echo "  bash ~/hans-sleep-yolo-mode/install.sh"
    exit 1
fi

echo -e "${BLUE}📁 安裝到: $CURRENT_DIR${NC}"
echo ""

# 檢查是否已安裝
if [ -f "CLAUDE.md" ]; then
    echo -e "${YELLOW}⚠️  偵測到已存在 CLAUDE.md${NC}"
    read -p "要覆蓋嗎？[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi
fi

# 複製檔案
echo -e "${BLUE}📋 複製檔案...${NC}"
cp "$SCRIPT_DIR/CLAUDE.md" .
cp "$SCRIPT_DIR/sleep-safe-runner.sh" .
mkdir -p .claude/skills/autonomous-skill
cp "$SCRIPT_DIR/.claude/settings.json" .claude/
cp "$SCRIPT_DIR/.claude/skills/autonomous-skill/SKILL.md" .claude/skills/autonomous-skill/

# 給執行權限
chmod +x sleep-safe-runner.sh

# 更新 .gitignore
if [ -f ".gitignore" ]; then
    if ! grep -q "\.autonomous/" .gitignore 2>/dev/null; then
        {
            echo ""
            echo "# Claude Code autonomous tasks"
            echo ".autonomous/"
        } >> .gitignore
    fi
else
    {
        echo "# Claude Code autonomous tasks"
        echo ".autonomous/"
    } > .gitignore
fi

echo ""
echo -e "${GREEN}✅ 安裝完成！${NC}"
echo ""
echo "已安裝："
echo "  📄 CLAUDE.md"
echo "  📄 sleep-safe-runner.sh"
echo "  📁 .claude/"
echo ""

# ============ 通知設定引導 ============
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📱 設定手機通知（讓你在睡覺時收到完成通知）${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "選你已經在用的服務（不需要全部設定）："
echo ""
echo -e "${BLUE}1) Discord webhook${NC}（已有 Discord 的話最快，不用裝新 app）"
echo "   Server Settings → Integrations → Webhooks → New Webhook → Copy URL"
echo ""
echo -e "${BLUE}2) ntfy.sh${NC}（沒有 Discord 的話推薦，免費，需安裝 ntfy app）"
echo "   手機下載 ntfy app，訂閱一個頻道"
echo ""
echo -e "${BLUE}3) 略過${NC}（之後再設定）"
echo ""
read -p "選擇 [1/2/3，預設 3]: " NOTIFY_CHOICE
NOTIFY_CHOICE="${NOTIFY_CHOICE:-3}"
echo ""

if [[ "$NOTIFY_CHOICE" == "1" ]]; then
    read -p "貼上 Discord Webhook URL: " DISCORD_WEBHOOK
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^DISCORD_WEBHOOK=\"\"|DISCORD_WEBHOOK=\"$DISCORD_WEBHOOK\"|" sleep-safe-runner.sh
        else
            sed -i "s|^DISCORD_WEBHOOK=\"\"|DISCORD_WEBHOOK=\"$DISCORD_WEBHOOK\"|" sleep-safe-runner.sh
        fi
        echo -e "${BLUE}🔔 測試通知中...${NC}"
        if curl -s -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d '{"content": "✅ Hans Sleep YOLO Mode 安裝成功！"}' > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 通知已送出！請確認 Discord 是否收到。${NC}"
        else
            echo -e "${YELLOW}⚠️  無法送出測試通知，請確認 webhook URL 是否正確。${NC}"
        fi
    fi

elif [[ "$NOTIFY_CHOICE" == "2" ]]; then
    echo "請先在手機的 ntfy app 裡訂閱一個頻道（例如 my-claude-abc123）"
    read -p "輸入你取的頻道名稱: " NTFY_TOPIC
    if [[ -n "$NTFY_TOPIC" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s/^NTFY_TOPIC=\"\"/NTFY_TOPIC=\"$NTFY_TOPIC\"/" sleep-safe-runner.sh
        else
            sed -i "s/^NTFY_TOPIC=\"\"/NTFY_TOPIC=\"$NTFY_TOPIC\"/" sleep-safe-runner.sh
        fi
        echo -e "${BLUE}🔔 測試通知中...${NC}"
        if curl -s -d "✅ Hans Sleep YOLO Mode 安裝成功！" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 通知已送出！請確認手機 ntfy app 是否收到。${NC}"
        else
            echo -e "${YELLOW}⚠️  無法送出測試通知，請確認網路連線。${NC}"
        fi
        echo -e "${GREEN}📱 ntfy 頻道已設定：$NTFY_TOPIC${NC}"
    fi

else
    echo -e "${YELLOW}⚠️  已略過通知設定。"
    echo "   之後可以編輯 sleep-safe-runner.sh 填入通知設定。${NC}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 啟動方式${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "直接啟動 YOLO Mode："
echo "  claude --dangerously-skip-permissions"
echo ""
echo "設定 alias（只需一次，之後輸入 yolo 就能啟動）："
if [[ "$(uname)" == "Darwin" ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
else
    SHELL_CONFIG="$HOME/.bashrc"
fi
echo "  echo 'alias yolo=\"claude --dangerously-skip-permissions\"' >> $SHELL_CONFIG && source $SHELL_CONFIG"
echo ""
echo "睡覺跑模式："
echo "  git checkout -b auto/my-feature"
echo "  ./sleep-safe-runner.sh \"用一句話描述你的任務\""
echo ""
echo -e "${GREEN}詳細說明請看 README.md${NC}"
echo ""
