# 🚀 Hans Sleep YOLO Mode

> **讓 Claude AI 更自主地工作，你可以去睡覺、明天再回來看成果。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.1+-blue)](https://claude.ai)

---

## 📖 詳細目錄

- [先看懂這個工具](#-先看懂這個工具)
  - [一句話版本](#一句話版本)
  - [它和 `claude --dangerously-skip-permissions` 到底差在哪](#它和-claude---dangerously-skip-permissions-到底差在哪)
  - [哪些能力本來就是 Claude Code 內建](#哪些能力本來就是-claude-code-內建)
  - [這個 repo 額外幫你做了什麼](#這個-repo-額外幫你做了什麼)
  - [這個專案裡有哪些檔案](#這個專案裡有哪些檔案)
- [費用 / Quota 說明](#-費用--quota-說明)
- [什麼任務適合 / 不適合](#-什麼任務適合--不適合)
  - [適合交給 AI 睡覺跑的任務](#適合交給-ai-睡覺跑的任務)
  - [不適合或容易失敗的任務](#不適合或容易失敗的任務)
  - [怎麼寫出比較不會翻車的任務描述](#怎麼寫出比較不會翻車的任務描述)
- [選擇你的使用路徑](#️-選擇你的使用路徑)
  - [路徑 A：完全不想碰終端機](#-路徑-a完全不想碰終端機)
  - [路徑 B：Mac 使用者（終端機）](#-路徑-bmac-使用者終端機)
  - [路徑 C：Windows 使用者](#-路徑-cwindows-使用者)
  - [路徑 D：完整睡覺跑模式](#-路徑-d完整睡覺跑模式)
- [路徑 A：完全不想碰終端機](#-路徑-a完全不想碰終端機-1)
  - [A-1. Claude Code 桌面版](#a-1-claude-code-桌面版推薦)
  - [A-2. Claude.ai 網頁版](#a-2-claudeai-網頁版)
- [路徑 B：Mac 使用者（終端機）](#-路徑-bmac-使用者終端機-1)
  - [B-0. 先知道你會做什麼](#b-0-先知道你會做什麼)
  - [B-1. 打開終端機](#b-1-打開終端機)
  - [B-2. 安裝 Node.js](#b-2-安裝-nodejs)
  - [B-3. 安裝 Claude Code](#b-3-安裝-claude-code)
  - [B-4. 登入 Claude](#b-4-登入-claude)
  - [B-5. 下載這個 repo](#b-5-下載這個-repo)
  - [B-6. 把設定安裝到你的專案](#b-6-把設定安裝到你的專案)
  - [B-7. 啟動 YOLO Mode](#b-7-啟動-yolo-mode)
  - [B-8. 設定快捷指令 yolo](#b-8-設定快捷指令-yolo強烈推薦)
- [路徑 C：Windows 使用者](#-路徑-cwindows-使用者-1)
  - [C-1. 最簡單：桌面版](#c-1-最簡單桌面版)
  - [C-2. 完整功能：WSL + 終端機](#c-2-完整功能wsl--終端機)
- [路徑 D：完整睡覺跑模式](#-路徑-d完整睡覺跑模式-1)
  - [D-1. 先設定通知](#d-1-先設定通知)
  - [D-2. 一定要切到 feature branch](#d-2-一定要切到-feature-branch)
  - [D-3. 啟動睡覺跑](#d-3-啟動睡覺跑)
  - [D-4. 關掉終端機也繼續跑（tmux）](#d-4-關掉終端機也繼續跑tmux)
  - [D-5. 起床後怎麼看結果](#d-5-起床後怎麼看結果)
  - [D-6. 常用參數調整](#d-6-常用參數調整)
- [檔案說明](#-檔案說明)
- [安全警告](#️-安全警告使用前必讀)
- [常見問題](#-常見問題)
  - [還是一直跳權限確認怎麼辦](#還是一直跳權限確認怎麼辦)
  - [跑到一半停了怎麼辦](#跑到一半停了怎麼辦)
  - [怎麼強制停止](#怎麼強制停止)
  - [跑完後怎麼合回 main](#跑完後怎麼合回-main)
  - [這跟 Cursor / GitHub Copilot 有什麼不同](#這跟-cursor--github-copilot-有什麼不同)
- [貢獻](#-貢獻)
- [授權](#-授權)

---

## 🤔 先看懂這個工具

### 一句話版本

**這個 repo 不是要取代 `claude --dangerously-skip-permissions`，而是把它包成一套「新手也比較能直接用」的工作流。**

如果你只想要一個最短答案，可以這樣理解：

- `claude --dangerously-skip-permissions`：**把權限確認關掉**
- `CLAUDE.md`：**告訴 Claude 做事風格**（少問問題、自己決定、遇錯自己修）
- `sleep-safe-runner.sh`：**讓任務可以長時間自動循環執行**，失敗重試、定期 checkpoint、記錄進度、送通知
- `install.sh`：**幫你把上面這些東西一次裝進你的專案**

所以答案是：**對，很多能力本來就是 Claude Code 內建；但這個專案把分散的做法整理成可以直接照著做的版本，還補上內建沒有直接提供的睡覺跑腳本。**

---

### 它和 `claude --dangerously-skip-permissions` 到底差在哪

| 你想要的效果 | 只用 `claude --dangerously-skip-permissions` | 用這個 repo |
|---|---|---|
| 不要每個 bash / 檔案操作都跳確認 | ✅ 可以 | ✅ 可以 |
| 讓 Claude 更少用文字問你問題 | ⚠️ 要自己額外寫 prompt 或 `CLAUDE.md` | ✅ 已附 `CLAUDE.md` |
| 把設定快速安裝到別的專案 | ❌ 要自己手動複製 | ✅ `install.sh` 一鍵安裝 |
| 任務失敗後自動再跑一次 | ❌ 沒有 | ✅ `sleep-safe-runner.sh` 會重試 |
| 長任務定期 commit checkpoint | ❌ 沒有 | ✅ 內建 checkpoint |
| 手機通知任務開始 / 完成 / 失敗 | ❌ 沒有 | ✅ 內建通知 |
| 追蹤任務清單與進度 | ❌ 沒有 | ✅ `.autonomous/<task>/task_list.md` |
| 完整新手教學 | ❌ 需要自己摸索 | ✅ 本 README 就是教學 |

---

### 哪些能力本來就是 Claude Code 內建

這個問題很重要，先講清楚：

**以下能力，本來就可以直接靠 Claude Code 做到：**

1. 使用 `claude --dangerously-skip-permissions` 跳過操作確認
2. 在對話中要求 Claude「不要問問題、自己做決定」
3. 直接請 Claude 幫你改程式、跑測試、修 bug
4. 手動在桌面版 / CLI 裡切換更高權限模式

也就是說，**如果你是熟手，很多事情你自己手動設定也做得到。**

---

### 這個 repo 額外幫你做了什麼

這個 repo 的價值主要在 4 件事：

1. **幫新手整理流程**
   - 不用自己猜要先裝什麼、先開什麼模式、提示詞該怎麼寫。
2. **提供可重用的 `CLAUDE.md`**
   - 不必每次重新打一長串「不要問我、自己修」的提示詞。
3. **提供睡覺跑腳本**
   - 這是和單純執行 `claude --dangerously-skip-permissions` 最大的差別。
   - 它會做循環執行、重試、checkpoint、進度追蹤、通知。
4. **提供一鍵安裝**
   - 你把這套設定裝進自己的專案，就能重複使用。

如果你只需要「跳過確認視窗」，**只打 CLI 旗標就夠了**。

如果你要的是「少問問題 + 有一套可複製流程 + 能整晚自己跑」，**這個 repo 才有意義**。

---

### 這個專案裡有哪些檔案

| 檔案 | 用途 | 你什麼時候會用到 |
|------|------|------------------|
| `README.md` | 你現在正在看的新手教學 | 第一次使用時 |
| `CLAUDE.md` | Claude 的行為規則 | 想讓它更自主時 |
| `sleep-safe-runner.sh` | 長任務自動循環腳本 | 想「睡覺跑」時 |
| `install.sh` | 一鍵把設定複製到你的專案 | 想把這套流程裝到別的 repo 時 |
| `.claude/settings.json` | Claude 本地設定 | 安裝後自動帶進去 |
| `.claude/skills/autonomous-skill/SKILL.md` | 長任務技能定義 | 由安裝腳本一起帶入 |

---

## 💰 費用 / Quota 說明

### 需要哪個方案？

| 方案 | 月費 | 可以用嗎？ |
|------|------|-----------|
| Claude Free | 免費 | ❌ 不支援 Claude Code |
| **Claude Max** | 約 USD 100/月 | ✅ 個人使用最常見 |
| **Claude Team** | 約 USD 30/人/月 | ✅ 團隊使用 |
| Claude API | 依用量計費 | ✅ 進階使用者可自行整合 |

> 最新價格請依 [claude.ai](https://claude.ai) 官方頁面為準。

### 跑一整晚會吃多少 quota？

沒有固定答案，取決於任務大小。

大致可以抓：

- 簡單任務（10-20 個小步驟）：約 2-4 小時、20-40 輪
- 中型任務（30-50 個步驟）：約 4-8 小時、40-80 輪
- 很大的任務：有可能會碰到 rate limit，腳本會等待後重試

### 新手建議：先跑小任務測試

第一次不要直接丟一整晚的大案子，先測試流程：

```bash
# 先把腳本內的 MAX_ITERATIONS 改成 10
./sleep-safe-runner.sh "test-run" "A small test task to verify the setup works"
```

如果小任務可以順利跑完，再開整晚模式。

---

## 🎯 什麼任務適合 / 不適合

### 適合交給 AI 睡覺跑的任務

| 任務類型 | 範例 |
|---------|------|
| 建立新功能 | 「加入 JWT 登入驗證」、「建立商品 CRUD API」 |
| 寫測試 | 「幫現有所有 API 補上 unit tests」 |
| 重構 | 「把這個模組從 JavaScript 改成 TypeScript」 |
| 文件 | 「幫所有函數加上 JSDoc 註解」 |
| 遷移腳本 | 「把舊資料格式轉成新格式」 |
| Bug 修復 | 「修這些 failing tests：[貼上錯誤訊息]」 |

### 不適合或容易失敗的任務

| 問題類型 | 為什麼容易失敗 |
|---------|----------------|
| 「把整個 app 重寫」 | 太模糊，Claude 不知道從哪裡開始 |
| 需要你拍板的設計選擇 | AI 會自己決定，但不一定符合你的偏好 |
| 需要外部服務權限 | 沒有 API key / 帳號就做不完 |
| 高度主觀的 UI/UX 調整 | 好不好看很難自動判斷 |
| 「修所有 bug」 | 沒有範圍，容易無限擴張 |

### 怎麼寫出比較不會翻車的任務描述

原則很簡單：**你自己看得懂、能驗收的規格，Claude 才比較做得好。**

#### 不夠好的寫法

```text
幫我把搜尋功能做好。
```

問題：太短、太模糊，不知道要改前端、後端，還是資料庫。

#### 比較好的寫法

```bash
./sleep-safe-runner.sh "add-search" \
  "Add full-text search to the product listing page using the existing PostgreSQL database.
   Include: search API endpoint with pagination, debounced frontend input,
   highlight matching terms in results, and test coverage."
```

因為它清楚說明了：

- 做哪個功能
- 用哪個資料來源
- 要包含哪些子功能
- 要不要補測試

---

## 🗺️ 選擇你的使用路徑

| 路徑 | 適合誰 | 你會得到什麼 |
|------|--------|--------------|
| **A：完全不想碰終端機** | 完全新手、先想體驗概念 | 基本版 YOLO 工作流 |
| **B：Mac + 終端機** | Mac 使用者，願意複製貼上指令 | 完整安裝能力 |
| **C：Windows** | Windows 使用者 | 桌面版或 WSL 完整功能 |
| **D：完整睡覺跑模式** | 已完成 B 或 C，想整晚自動跑 | 循環執行 + 通知 + 進度追蹤 |

> **如果你完全是新手，建議順序：A → B/C → D。**

---

## 💻 路徑 A：完全不想碰終端機

這條路最適合：

- 你完全不想裝終端機工具
- 你只是想先感受「Claude 更自主」的效果
- 你現在不需要整晚背景執行

### 你會得到什麼

- Claude 比較少問你問題
- 你可以直接在桌面版 / 網頁版下任務
- **但沒有** `sleep-safe-runner.sh` 的重試、通知、checkpoint 功能

> 如果你之後想要完整睡覺跑，再回來看路徑 B/C/D。

---

### A-1. Claude Code 桌面版（推薦）

#### 步驟 1：下載安裝桌面版

前往 [claude.ai/download](https://claude.ai/download) 下載並安裝。

第一次開啟會要求你登入 Claude 帳號。

#### 步驟 2：開啟你的專案資料夾

在桌面版中選擇 **Open Folder**，打開你要讓 Claude 幫你工作的專案。

#### 步驟 3：新增 `CLAUDE.md`

在專案根目錄建立一個文字檔，檔名叫 **`CLAUDE.md`**，把下面內容貼進去：

```markdown
## 自主工作模式

你正在以全自主模式工作。嚴格遵守以下規則：

1. **不要問問題** — 自己做決定，選最合理的選項
2. **不要等確認** — 直接執行
3. **遇到錯誤自己修** — 讀錯誤訊息，嘗試修復，繼續
4. **做完才停** — 完成整個任務再停止
5. **改完就 commit** — 每完成一個階段就 git commit

遇到不確定的情況：
- 多種解法 → 選最簡單的
- 缺少資訊 → 用合理預設值
- 需求衝突 → 照 codebase 現有 pattern
```

#### 步驟 4：切換權限模式

在 Claude Code 裡按 **Shift + Tab**，切到畫面左下角顯示類似：

- `auto-approve`
- `bypass permissions`

這代表 Claude 可以少掉大部分操作確認。

#### 步驟 5：直接交代任務

例如：

```text
幫我完成用戶登入功能。自己做決定，不要問我確認，遇到問題自己解決。
```

這樣你就已經在用「簡化版 YOLO Mode」了。

---

### A-2. Claude.ai 網頁版

如果你不想裝桌面版，也可以先用網頁版：

1. 前往 [claude.ai/code](https://claude.ai/code)
2. 登入 Claude 帳號
3. 在對話一開始先貼上上一節的 `CLAUDE.md` 內容
4. 再貼上你的任務描述

> 網頁版比較適合輕量使用。若你要跑本地腳本、長任務或背景工作，還是建議桌面版 / CLI。

---

## 🍎 路徑 B：Mac 使用者（終端機）

這條路適合你如果：

- 你用的是 Mac
- 你願意把指令一行一行複製貼上
- 你想使用完整版本的安裝流程

### B-0. 先知道你會做什麼

你等等會做 5 件事：

1. 打開終端機
2. 安裝 Node.js
3. 安裝 Claude Code
4. 下載這個 repo
5. 把設定安裝到你的專案，再用 `claude --dangerously-skip-permissions` 啟動

不用怕看不懂指令，**照順序一行一行貼就可以。**

---

### B-1. 打開終端機

#### 方法一（最快）

1. 按 **⌘ Command + 空白鍵**
2. 輸入 `Terminal`
3. 按 Enter

#### 方法二

Finder → 應用程式 → 工具程式 → 終端機

打開後你會看到類似：

```bash
使用者名稱@電腦名稱 ~ %
```

這就代表終端機已經開好了；你的畫面會顯示你自己的使用者名稱和電腦名稱，例如 `hans@MacBook-Air ~ %`。

---

### B-2. 安裝 Node.js

#### 先安裝 Homebrew（Mac 常用套件管理工具）

把下面這一行貼進終端機：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

如果系統要求輸入密碼：

- 直接輸入你的 Mac 登入密碼
- 畫面不會顯示字元是正常的
- 打完按 Enter 即可

#### 再安裝 Node.js

```bash
brew install node
```

#### 確認安裝成功

```bash
node --version
```

如果看到像 `v20.x.x`，就表示成功。

---

### B-3. 安裝 Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

確認安裝成功：

```bash
claude --version
```

只要有顯示版本號就可以。

---

### B-4. 登入 Claude

```bash
claude
```

第一次執行通常會開瀏覽器要求登入授權。

流程是：

1. 瀏覽器打開
2. 你登入 Claude 帳號
3. 授權完成
4. 回到終端機

這樣就登入好了。

---

### B-5. 下載這個 repo

這一步只要做一次：

```bash
git clone https://github.com/hansai-art/hans-sleep-yolo-mode.git ~/hans-sleep-yolo-mode
```

這代表把本 repo 下載到你電腦的家目錄。

---

### B-6. 把設定安裝到你的專案

先切換到你要工作的專案資料夾：

```bash
cd ~/你的專案路徑
```

如果你不知道路徑，最簡單的方法是：

1. 在 Finder 找到你的專案資料夾
2. 把整個資料夾拖曳到終端機視窗
3. 終端機會自動幫你填入路徑

然後執行安裝：

```bash
bash ~/hans-sleep-yolo-mode/install.sh
```

安裝完成後，通常會把這些東西放進你的專案：

- `CLAUDE.md`
- `sleep-safe-runner.sh`
- `.claude/settings.json`
- `.claude/skills/autonomous-skill/SKILL.md`

---

### B-7. 啟動 YOLO Mode

```bash
claude --dangerously-skip-permissions
```

這個指令的意思是：

- 啟動 Claude Code CLI
- 跳過每次操作前的確認
- 讓 Claude 能更連續地執行工作

啟動後你就可以直接交代任務，例如：

```text
幫我整理這個專案的 ESLint 設定，修掉目前的 lint error，改完自己跑測試確認。
```

---

### B-8. 設定快捷指令 yolo（強烈推薦）

每次都輸入一長串指令很麻煩，可以設一個簡短指令：

```bash
echo 'alias yolo="claude --dangerously-skip-permissions"' >> ~/.zshrc && source ~/.zshrc
```

之後只要輸入：

```bash
yolo
```

就能啟動。

---

## 🪟 路徑 C：Windows 使用者

Windows 建議分成兩種情況：

- **完全新手**：先用桌面版
- **想用完整 CLI 功能**：用 WSL

### C-1. 最簡單：桌面版

1. 前往 [claude.ai/download](https://claude.ai/download)
2. 下載 Windows 桌面版
3. 安裝後，照著上面的 **路徑 A** 操作

這樣最容易上手。

---

### C-2. 完整功能：WSL + 終端機

WSL = Windows Subsystem for Linux。

簡單說，就是讓 Windows 可以跑 Linux 終端機，所以你才能用和 Mac / Linux 類似的方式執行 Claude Code CLI。

#### 步驟 1：安裝 WSL

1. 按 Windows 鍵
2. 搜尋 `PowerShell`
3. 右鍵 → **以系統管理員身分執行**
4. 貼上：

```powershell
wsl --install
```

5. 安裝完重新開機

#### 步驟 2：設定 Ubuntu

重新開機後，系統通常會自動引導你完成 Ubuntu 初始設定。

你需要設定：

- Linux 使用者名稱
- Linux 密碼

#### 步驟 3：安裝 Node.js 和 Claude Code

在 Ubuntu 視窗貼上：

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs
npm install -g @anthropic-ai/claude-code
```

#### 步驟 4：後面照 Mac 路徑繼續

從 **路徑 B 的步驟 4** 開始往下做即可。

> 在 WSL 裡，你的 Windows 檔案通常會出現在 `/mnt/c/Users/你的名字/`。

---

## 🌙 路徑 D：完整睡覺跑模式

> **前提：先完成路徑 B 或 C。**

這條路才是本 repo 最有特色的部分。

如果你只是開：

```bash
claude --dangerously-skip-permissions
```

那只是讓 Claude 比較不會一直跳確認。

**而睡覺跑模式多做的是：**

- 自動循環執行
- 失敗後再試
- 定期 git checkpoint
- 記錄任務清單
- 送手機通知

---

### D-1. 先設定通知

不一定要先設，但很推薦，因為你睡醒時才會知道它有沒有完成。

#### 選項一：Discord（最快）

適合已經在用 Discord 的人。

1. 打開 Discord
2. 進入一個你的 server
3. 打開 **Server Settings → Integrations → Webhooks → New Webhook**
4. 建立一個 webhook
5. 複製 webhook URL
6. 編輯 `sleep-safe-runner.sh`，把：

```bash
DISCORD_WEBHOOK=""
```

改成：

```bash
DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
```

測試：

```bash
curl -X POST "你的 webhook URL" \
  -H "Content-Type: application/json" \
  -d '{"content": "測試成功 🎉"}'
```

#### 選項二：ntfy.sh（沒有 Discord 時推薦）

1. 手機安裝 ntfy app
   - iPhone：[App Store](https://apps.apple.com/app/ntfy/id1625396347)
   - Android：[Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
2. 在 app 內建立一個頻道，例如 `hans-ai-abc123`
3. 編輯 `sleep-safe-runner.sh`，把：

```bash
NTFY_TOPIC=""
```

改成：

```bash
NTFY_TOPIC="你的頻道名"
```

4. 測試：

```bash
curl -d "測試成功 🎉" ntfy.sh/你的頻道名
```

#### 選項三：Telegram

1. 用 `@BotFather` 建立 bot
2. 拿到 bot token
3. 傳訊息給你的 bot
4. 用 `https://api.telegram.org/bot你的TOKEN/getUpdates` 找到 `chat_id`
5. 把下面兩行填進腳本：

```bash
TELEGRAM_BOT_TOKEN="你的token"
TELEGRAM_CHAT_ID="你的chat_id"
```

---

### D-2. 一定要切到 feature branch

> **不要直接在 `main` 或 `master` 上讓 AI 自動跑。**

在你的專案目錄執行：

```bash
git checkout -b auto/my-feature-name
```

這樣如果結果不滿意，比較容易回復。

---

### D-3. 啟動睡覺跑

最基本寫法：

```bash
./sleep-safe-runner.sh "任務名稱" "詳細說明（可選但強烈建議）"
```

#### 只有任務名稱

```bash
./sleep-safe-runner.sh "build-auth"
```

適合：你願意讓 Claude 自己發揮比較多。

#### 有詳細說明（推薦）

```bash
./sleep-safe-runner.sh "build-auth" "Build JWT authentication: login/register API, bcrypt password hashing, refresh token rotation, and middleware for protected routes"
```

適合：你想讓輸出更穩定、更接近你要的結果。

#### 兩個參數分別是什麼

- 第一個參數：**任務名稱**
  - 短一點、英文為主
  - 用來建立 `.autonomous/任務名稱/` 資料夾
- 第二個參數：**任務說明**
  - 真正告訴 Claude 要完成什麼
  - 建議越具體越好

啟動後，腳本會幫你做：

- 建立任務資料夾
- 追蹤待辦清單
- 定期 commit checkpoint
- 任務完成後通知你

這時候就可以去睡覺了 💤

---

### D-4. 關掉終端機也繼續跑（tmux）

如果你直接關掉終端機，程式通常會一起停掉。

想讓它在背景繼續跑，建議用 `tmux`。

#### 安裝 tmux

```bash
# Mac
brew install tmux

# Linux / WSL
sudo apt install tmux
```

#### 用 tmux 啟動

```bash
tmux new-session -d -s claude './sleep-safe-runner.sh "你的任務名稱"'
```

#### 查看目前狀態

```bash
tmux attach -t claude
```

看完要離開但不要停止：

1. 按 **Ctrl + B**
2. 再按 **D**

---

### D-5. 起床後怎麼看結果

#### 最快看法

```bash
# 看單一任務的進度、最近完成項目、下一步
./sleep-safe-runner.sh --status 你的任務名

# 列出所有任務
./sleep-safe-runner.sh --list
```

輸出範例：

```text
📊 Status: build-auth
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Progress: 18/24 tasks (75%)

✅ Recently completed:
   ✓ Create User model with bcrypt hashing
   ✓ Build POST /auth/register endpoint
   ✓ Build POST /auth/login endpoint
   ✓ Implement JWT token generation
   ✓ Add refresh token rotation

⏳ Next up:
   • Add auth middleware for protected routes
   • Write integration tests for auth flow
   • Update API documentation
```

#### 想看更細的內容

```bash
# 看完整任務清單
cat .autonomous/你的任務名/task_list.md

# 看最近 commit
git log --oneline -20

# 看詳細 log
cat .autonomous/你的任務名/logs/runner.log
```

---

### D-6. 常用參數調整

你可以直接編輯 `sleep-safe-runner.sh` 內這幾個值：

```bash
MAX_ITERATIONS=100           # 最大執行輪數
MAX_CONSECUTIVE_FAILURES=5   # 連續失敗上限
MAX_SESSION_MINUTES=45       # 單輪超時（分鐘）
CHECKPOINT_EVERY=3           # 每幾輪自動 git commit
```

補充：

- **timeout 不等於失敗**
- 如果某一輪只是跑太久，腳本會視為任務比較大，不一定直接停止
- 真正異常退出才會累積失敗次數

---

## 📦 檔案說明

```text
hans-sleep-yolo-mode/
├── README.md              # 這份新手教學
├── CLAUDE.md              # Claude 行為規則
├── sleep-safe-runner.sh   # 長任務循環腳本
├── install.sh             # 一鍵安裝腳本
├── LICENSE
└── .claude/
    ├── settings.json
    └── skills/autonomous-skill/
        └── SKILL.md
```

---

## ⚠️ 安全警告！使用前必讀

> **YOLO Mode = 權限全開 = 後果自負。**

開啟高權限模式後，Claude 可能可以：

- 執行 bash 指令
- 讀寫專案檔案
- 安裝套件
- 執行程式碼

### 安全建議

| 建議 | 原因 |
|------|------|
| 永遠在 feature branch 工作 | 出問題比較好回復 |
| 不要在有敏感資料的專案直接用 | 避免誤讀或誤提交機密 |
| 最好有備份 | 降低意外風險 |
| 起床後 review `git log` | 確認 AI 做了什麼 |
| 能用 VM / Container 更好 | 風險隔離更完整 |

> **請記得：就算 `CLAUDE.md` 寫了限制，也不代表 100% 絕對安全。重要專案仍然要自己 review。**

### `CLAUDE.md` 已禁止的危險操作

- `sudo` / `su`。
- 刪除系統檔案。
- commit 機密資訊（`.env`、API key 等）。
- push 到 remote。
- 對 production 資料做破壞性操作。

---

## ❓ 常見問題

### 我需要什麼帳號才能用？

通常需要 **Claude Max** 或 **Claude Team**，因為 Claude Code 不在免費方案內。

---

### 還是一直跳權限確認怎麼辦？

先確認你是不是用這個指令啟動：

```bash
claude --dangerously-skip-permissions
```

再確認左下角是不是有類似：

- `bypass permissions on`
- `auto-approve`

如果沒有，就按 **Shift + Tab** 切換模式。

---

### 跑到一半停了怎麼辦？

先看日誌：

```bash
cat .autonomous/你的任務名/logs/runner.log
```

常見原因：

- 額度用完
- 網路中斷
- 連續失敗超過上限

重新啟動通常會沿用原本進度：

```bash
./sleep-safe-runner.sh "同樣的任務名稱"
```

---

### 怎麼強制停止？

最直接的方式：

- 前景執行時按 **Ctrl + C**
- 如果你用 `tmux`，先 `tmux attach -t claude` 再按 **Ctrl + C**

---

### 跑完後怎麼合回 main？

```bash
# 先看 AI 做了哪些 commit
git log --oneline

# 確認沒問題再切回 main 合併
git checkout main
git merge auto/你的分支名稱
```

---

### `CLAUDE.md` 和 `claude --dangerously-skip-permissions` 到底要不要兩個都用？

**最短答案：建議兩個都用，但它們功能不同。**

| 項目 | 真正作用 |
|---|---|
| `claude --dangerously-skip-permissions` | 讓 Claude **不用每一步都跳權限確認** |
| `CLAUDE.md` | 讓 Claude **更傾向照你指定的工作風格做事** |

#### 只用旗標，不用 `CLAUDE.md`

會發生什麼？

- Claude 可以執行操作
- 但它還是可能在對話裡問你問題
- 做事風格比較沒有被固定下來

#### 只用 `CLAUDE.md`，不用旗標

會發生什麼？

- Claude 可能願意主動做事
- 但每次操作仍可能要你確認
- 體感上會一直被打斷

#### 兩個都用

效果最好，因為：

- 一個處理「權限」
- 一個處理「行為風格」

#### 那這個 repo 還有沒有必要？

如果你已經很熟 Claude Code，**不一定非用這個 repo 不可**。

但如果你是新手，或你想要：

- 可直接複製到新專案的設定
- 睡覺跑腳本
- 進度追蹤
- 通知機制
- 一份整理好的教學

那這個 repo 仍然有價值。

---

### 這跟 Cursor / GitHub Copilot 有什麼不同？

| 工具 | 比較像什麼 |
|------|------------|
| **Cursor** | 偏 IDE 協作，邊寫邊互動 |
| **GitHub Copilot** | 偏即時補全與小範圍協助 |
| **Claude Code + 本 repo** | 偏「交代一個完整任務，讓它長時間自己做」 |

---

## 🤝 貢獻

歡迎開 Issue 或 Pull Request。

如果這個專案對你有幫助，也歡迎幫忙點個 ⭐

---

## 📄 授權

MIT License

---

**Made with 💤 by Hans Lin — 讓 AI 工作，你去睡覺**
