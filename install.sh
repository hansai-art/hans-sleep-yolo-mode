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
cp "$SCRIPT_DIR/setup-wizard.sh" .
cp "$SCRIPT_DIR/.sleep-yolo.env.example" .
cp "$SCRIPT_DIR/.sleep-yolo.team.example.json" .
mkdir -p .claude/skills/autonomous-skill
cp "$SCRIPT_DIR/.claude/settings.json" .claude/
cp "$SCRIPT_DIR/.claude/skills/autonomous-skill/SKILL.md" .claude/skills/autonomous-skill/

# 給執行權限
chmod +x sleep-safe-runner.sh
chmod +x setup-wizard.sh

ensure_gitignore_entries() {
    local gitignore_file=".gitignore"

    touch "$gitignore_file"

    if ! grep -Fq '# Claude Code autonomous tasks' "$gitignore_file" 2>/dev/null; then
        {
            echo ""
            echo "# Claude Code autonomous tasks"
        } >> "$gitignore_file"
    fi

    if ! grep -q '^\.autonomous/$' "$gitignore_file" 2>/dev/null; then
        echo ".autonomous/" >> "$gitignore_file"
    fi

    if ! grep -q '^\.sleep-yolo\.env$' "$gitignore_file" 2>/dev/null; then
        echo ".sleep-yolo.env" >> "$gitignore_file"
    fi
}

# 更新 .gitignore
ensure_gitignore_entries

echo ""
echo -e "${GREEN}✅ 安裝完成！${NC}"
echo ""
echo "已安裝："
echo "  📄 CLAUDE.md"
echo "  📄 sleep-safe-runner.sh"
echo "  📄 setup-wizard.sh"
echo "  📄 .sleep-yolo.env.example"
echo "  📄 .sleep-yolo.team.example.json"
echo "  📁 .claude/"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 啟動方式${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "第一次建議先跑設定精靈："
echo "  ./setup-wizard.sh"
echo "  ./sleep-safe-runner.sh --doctor"
echo "  ./sleep-safe-runner.sh --notify-test"
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
echo "  ./setup-wizard.sh"
echo "  ./sleep-safe-runner.sh \"用一句話描述你的任務\""
echo ""
echo -e "${GREEN}詳細說明請看 README.md${NC}"
echo ""

read -p "要現在啟動 setup-wizard.sh 嗎？[y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./setup-wizard.sh
fi
