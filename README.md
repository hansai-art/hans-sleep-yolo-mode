# 🚀 Hans Sleep YOLO Mode

> **讓 Claude AI 全自動工作，你安心去睡覺**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.1+-blue)](https://claude.ai)

---

## 📖 目錄

- [這是什麼？](#-這是什麼)
- [費用 / Quota 說明](#-費用--quota-說明)
- [什麼任務適合 / 不適合](#-什麼任務適合--不適合)
- [選擇你的路徑](#️-選擇你的路徑)
- [路徑 A：不想裝任何東西（桌面版 / 網頁版）](#-路徑-a不想裝任何東西桌面版--網頁版)
- [路徑 B：Mac 使用者（終端機）](#-路徑-bmac-使用者終端機)
- [路徑 C：Windows 使用者](#-路徑-cwindows-使用者)
- [路徑 D：完整睡覺跑模式](#-路徑-d完整睡覺跑模式進階)
- [安全警告](#️-安全警告使用前必讀)
- [常見問題](#-常見問題)

---

## 🤔 這是什麼？

**問題：** Claude Code 每執行一個動作就要問你「可以嗎？」，沒辦法讓它自己跑一整晚。

**解決：** Hans Sleep YOLO Mode 讓 Claude 自主工作，不打斷你，可以在你睡覺時自己把任務做完。

```
🌙 晚上 11 點
   ↓ 告訴 Claude：「幫我把這個功能做完」
   ↓ 去睡覺 💤
   
☀️ 早上 8 點
   ↓ 起床，任務已完成
   ↓ 看 git log，review 成果
```

### 它包含什麼？

| 檔案 | 用途 |
|------|------|
| `CLAUDE.md` | 告訴 Claude「不問問題、自己決定、遇到錯誤自己修」 |
| `sleep-safe-runner.sh` | 讓 Claude 在背景自動循環跑，失敗自動重試，完成發手機通知 |
| `setup-wizard.sh` | 互動式建立通知與 runner 設定 |
| `install.sh` | 一鍵把設定安裝到你的專案 |

**新手先記住兩個檢查指令：**
```bash
./sleep-safe-runner.sh --doctor
./sleep-safe-runner.sh --notify-test
```

---

## 💰 費用 / Quota 說明

**需要哪個方案？**

| 方案 | 月費 | 可以用嗎？ |
|------|------|-----------|
| Claude Free | 免費 | ❌ 不支援 Claude Code |
| **Claude Max** | ~USD $100/月 | ✅ 個人推薦，含大量 Claude Code 使用量 |
| **Claude Team** | ~USD $30/人/月 | ✅ 團隊使用 |
| Claude API | 依用量計費 | ✅ 需要自己設定 API key |

> 前往 [claude.ai](https://claude.ai) 查看最新方案定價。

**跑一整晚要多少 quota？**

沒有固定答案，取決於任務複雜度。幾個參考數字：

- 簡單任務（10-20 個小步驟）：約 2-4 小時、20-40 輪
- 中型功能（30-50 個步驟）：約 4-8 小時、40-80 輪
- **Claude Max 方案有 rate limit**，高強度使用可能在凌晨觸發速率限制，腳本會繼續重試

**建議：第一次先跑 10 輪測試**

```bash
# 先小試看看，確認流程沒問題再跑整晚
MAX_ITERATIONS=10  # 在腳本裡先改成 10
./sleep-safe-runner.sh "test-run" "A small test task to verify the setup works"
```

---

## 🎯 什麼任務適合 / 不適合

### ✅ 適合交給 AI 睡覺跑的任務

| 任務類型 | 範例 |
|---------|------|
| 建立新功能 | 「加入 JWT 登入驗證」、「建立商品 CRUD API」 |
| 寫測試 | 「幫現有所有 API 補上 unit tests」 |
| 重構 | 「把這個模組從 JavaScript 改成 TypeScript」 |
| 文件 | 「幫所有函數加上 JSDoc 註解」 |
| 資料遷移腳本 | 「寫一個把舊資料格式轉成新格式的腳本」 |
| Bug 修復（有明確錯誤訊息） | 「修這些 failing tests：[貼上錯誤訊息]」 |

**好的任務描述長這樣：**
```bash
./sleep-safe-runner.sh "add-search" \
  "Add full-text search to the product listing page using the existing PostgreSQL database.
   Include: search API endpoint with pagination, debounced frontend input,
   highlight matching terms in results, and test coverage."
```

### ❌ 不適合 / 容易失敗的任務

| 問題類型 | 原因 |
|---------|------|
| 「把整個 app 重寫」 | 太模糊，Claude 不知道從哪裡開始 |
| 需要你做決定的設計問題 | Claude 會自己做決定，結果可能不是你要的 |
| 需要存取外部服務（沒有 key） | Claude 無法取得缺少的 API key |
| UI/UX 設計調整 | 涉及主觀判斷，結果難以預期 |
| 「修所有 bug」 | 沒有具體目標，容易繞圈子 |

**關鍵原則：**
> 能讓你自己寫出清楚 spec 的任務，AI 就能做得好。模糊的任務給 AI 也一樣模糊。

---

## 🗺️ 選擇你的路徑

**你是哪一種使用者？**

| 路徑 | 適合你嗎？ | 功能 |
|------|-----------|------|
| **A：桌面版 / 網頁版** | 不想裝任何東西 | 基本 YOLO Mode（減少問問題） |
| **B：Mac + 終端機** | Mac 使用者，願意學一點終端機 | 完整功能 |
| **C：Windows** | Windows 使用者 | 完整功能 |
| **D：睡覺跑模式** | 已完成 B 或 C，想讓 AI 跑整晚 | 全自動循環 + 手機通知 |

> 💡 **不確定選哪個？** 從路徑 A 開始，確認概念有用之後再升級到 B/C/D。

---

## 💻 路徑 A：不想裝任何東西（桌面版 / 網頁版）

這個方法讓 Claude 少問問題、更自主工作。**不需要終端機、不需要安裝任何東西。**

> ⚠️ 路徑 A 不包含「睡覺跑自動循環」功能。要完整功能請看路徑 D。

---

### 方法一：Claude Code 桌面版（推薦）

**步驟 1：下載安裝桌面版**

前往 [claude.ai/download](https://claude.ai/download)，下載 Mac 或 Windows 版本並安裝。

第一次開啟會要求登入你的 Claude 帳號（需要 Claude Max 或 Team 方案）。

---

**步驟 2：開啟你的專案資料夾**

在桌面版裡選擇「Open Folder」，選你要讓 AI 工作的資料夾。

---

**步驟 3：放入 CLAUDE.md**

在你的專案資料夾裡，新增一個叫 `CLAUDE.md` 的文字檔（記事本就可以建立），把以下內容**完整複製貼進去**然後儲存：

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

---

**步驟 4：切換到 Auto-approve 模式**

在 Claude Code 裡，按 **Shift + Tab** 切換權限模式，直到左下角顯示類似 **`auto-approve`** 或 **`bypass permissions`**。

---

**步驟 5：開始工作！**

在對話框輸入你的任務，例如：

```
幫我完成用戶登入功能。自己做決定，不要問我確認，遇到問題自己解決。
```

Claude 就會自主工作了 ✅

---

### 方法二：Claude.ai 網頁版

1. 打開瀏覽器，前往 **[claude.ai/code](https://claude.ai/code)**
2. 登入你的 Claude 帳號
3. 在對話框最前面，先貼上上方「步驟 3」的 CLAUDE.md 內容
4. 然後輸入你的任務

> 網頁版有部分功能限制（例如執行本地腳本），適合輕量使用。

---

## 🍎 路徑 B：Mac 使用者（終端機）

### 步驟 1：打開終端機

**方法一（最快）：**
1. 按鍵盤的 **⌘ Command + 空白鍵**
2. 搜尋框輸入 `Terminal`（或「終端機」）
3. 按 Enter

**方法二：**
Finder → 應用程式 → 工具程式 → 終端機

你會看到一個視窗，裡面顯示：
```
你的名字@電腦名稱 ~ %
```
這代表終端機已開啟，可以輸入指令了。

---

### 步驟 2：安裝必要工具

把每一行**分開複製貼上**，等它跑完再貼下一行：

**安裝 Homebrew（Mac 套件管理工具）：**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
> 安裝過程中可能要輸入你的電腦密碼。輸入密碼時畫面不會顯示字，這是正常的，直接打完按 Enter。

**安裝 Node.js：**
```bash
brew install node
```

**確認安裝成功：**
```bash
node --version
```
看到 `v20.x.x` 就成功了 ✅

---

### 步驟 3：安裝 Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

**確認安裝成功：**
```bash
claude --version
```

---

### 步驟 4：登入 Claude

```bash
claude
```

第一次執行會開啟瀏覽器要你授權登入，在瀏覽器完成後回到終端機就好。

---

### 步驟 5：下載並安裝 YOLO Mode 設定

```bash
# 下載設定（只需執行一次）
git clone https://github.com/hansai-art/hans-sleep-yolo-mode.git ~/hans-sleep-yolo-mode
```

然後進入你要開發的專案資料夾：
```bash
cd ~/你的專案路徑
```

> 不知道路徑？在 Finder 中找到你的專案資料夾，把資料夾**拖曳**進終端機視窗，它會自動填入路徑。

安裝設定：
```bash
bash ~/hans-sleep-yolo-mode/install.sh
```

第一次安裝後，建議再跑一次設定精靈：
```bash
./setup-wizard.sh
```

---

### 步驟 6：啟動 YOLO Mode

```bash
claude --dangerously-skip-permissions
```

Claude 啟動後，告訴它你要做什麼，它會自己工作、不問問題！

---

### 設定快捷指令（強烈推薦，只需執行一次）

每次打 `claude --dangerously-skip-permissions` 很麻煩，設定一個短指令：

```bash
echo 'alias yolo="claude --dangerously-skip-permissions"' >> ~/.zshrc && source ~/.zshrc
```

以後只要輸入 `yolo` 就能啟動！

---

## 🪟 路徑 C：Windows 使用者

Windows 有兩種方式，**建議先從 A 路徑的桌面版開始**，想要完整功能再用方法二。

---

### 方法一：Windows 桌面版（最簡單）

前往 [claude.ai/download](https://claude.ai/download)，下載 Windows 版本，安裝完成後參考上方**路徑 A** 的說明。

---

### 方法二：WSL + 終端機（完整功能）

WSL = Windows Subsystem for Linux，讓 Windows 也能跑 Linux 指令。

**步驟 1：安裝 WSL**

按 **Windows 鍵**，搜尋 `PowerShell`，右鍵選擇 **「以系統管理員身分執行」**。

貼上這個指令然後按 Enter：
```powershell
wsl --install
```

安裝完成後**重新開機**。

---

**步驟 2：設定 Ubuntu**

重開機後系統會自動開啟 Ubuntu 視窗，設定你的 Linux 使用者名稱和密碼（這跟你的 Windows 帳號不同）。

---

**步驟 3：安裝 Node.js 和 Claude Code**

在 Ubuntu 視窗貼上：
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs
```

然後安裝 Claude Code：
```bash
npm install -g @anthropic-ai/claude-code
```

---

**步驟 4：後續步驟同 Mac**

從路徑 B 的「步驟 4」繼續，方式完全一樣。

> **注意**：在 WSL 裡操作時，你的 Windows 檔案在 `/mnt/c/Users/你的名字/` 這個路徑下。

---

## 🌙 路徑 D：完整睡覺跑模式（進階）

> **前提：** 先完成路徑 B 或 C。

這是完整功能：讓 Claude 在你睡覺時跑整晚，自動循環執行任務，每隔一段時間發手機通知給你。

---

### 步驟 1：設定手機通知

強烈建議先設定，不然你不知道任務有沒有完成。選你**已經在用的服務**，不用全部都設：

---

#### 選項一：Discord（已有 Discord 的話最快 — 不用裝任何新 app）

1. 打開 Discord，進入任意一個你的 server（或建立一個私人 server）
2. 點右上角的齒輪 **⚙️ Server Settings**
3. 左側選 **Integrations → Webhooks → New Webhook**
4. 取個名字（例如 `Claude Notify`），選要發到哪個 channel
5. 點 **Copy Webhook URL**

把這個 URL 填進設定檔：
```bash
cp .sleep-yolo.env.example .sleep-yolo.env
nano .sleep-yolo.env
# 找到：DISCORD_WEBHOOK=
# 改成：DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
```

測試：
```bash
curl -X POST "你的 webhook URL" \
  -H "Content-Type: application/json" \
  -d '{"content": "測試成功 🎉"}'
```

---

#### 選項二：ntfy.sh（沒有 Discord/Telegram 的話推薦）

需要裝一個新 app，但之後最簡單。

**1. 手機下載 ntfy app：**
- iPhone：[App Store](https://apps.apple.com/app/ntfy/id1625396347)
- Android：[Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy)

**2. 建立通知頻道：**

打開 app，點右上角 **+**，輸入頻道名稱，例如：`hans-ai-abc123`

> ⚠️ 頻道名稱是**公開的**，請取一個不容易猜到的名字，加上隨機數字。

**3. 填入設定並測試：**

```bash
nano .sleep-yolo.env
# 找到：NTFY_TOPIC=
# 改成：NTFY_TOPIC=你的頻道名
```

測試：
```bash
curl -d "測試成功 🎉" ntfy.sh/你的頻道名
```
手機收到通知就成功 ✅

---

#### 選項三：Telegram（有 Telegram 的話免費無限則）

1. 在 Telegram 搜尋 `@BotFather`，傳 `/newbot` 建立一個 bot，取得 Token
2. 搜尋你剛建的 bot，傳它任何一條訊息
3. 開啟瀏覽器，輸入 `https://api.telegram.org/bot你的TOKEN/getUpdates`，從結果找到 `chat_id`

填入 `.sleep-yolo.env`：
```bash
TELEGRAM_BOT_TOKEN=你的token
TELEGRAM_CHAT_ID=你的chat_id
```

---

### 步驟 2：確認在 feature branch

> ⚠️ **非常重要**：絕對不要在 `main` 或 `master` 分支直接跑，這樣萬一出問題可以輕易復原。

```bash
cd ~/你的專案路徑

# 建立並切換到新分支
git checkout -b auto/my-feature-name
```

---

### 步驟 3：啟動！

> 💡 如果你還沒設定通知或想調整 runner 參數，先執行 `./setup-wizard.sh`。

第一次建議先確認環境真的 ready：
```bash
./sleep-safe-runner.sh --doctor
./sleep-safe-runner.sh --notify-test
```

如果中途 task metadata 損壞或缺檔，先修復再續跑：
```bash
./sleep-safe-runner.sh --repair 你的任務名
```

```bash
./sleep-safe-runner.sh "任務名稱" "詳細說明（可選但強烈建議）"
```

**只有名稱（Claude 會自己想）：**
```bash
./sleep-safe-runner.sh "build-auth"
```

**加上說明（Claude 做得更準確）：**
```bash
./sleep-safe-runner.sh "build-auth" "Build JWT authentication: login/register API, bcrypt password hashing, refresh token rotation, and middleware for protected routes"
```

> 💡 第一個參數是**任務名稱**（短英文，用於建立資料夾），第二個參數是**詳細說明**（告訴 Claude 實際要做什麼）。

Claude 會先把任務拆解成 10-30 個小步驟，然後一個一個完成，每 3 輪自動 commit，完成後發手機通知。

**現在可以去睡覺了 💤**

---

### 關掉終端機也繼續跑（推薦）

預設情況下關掉終端機視窗就會停止。用 tmux 可以讓它在背景繼續：

**安裝 tmux（只需一次）：**
```bash
# Mac：
brew install tmux

# Linux / WSL：
sudo apt install tmux
```

**用 tmux 啟動：**
```bash
tmux new-session -d -s claude './sleep-safe-runner.sh "你的任務名稱"'
```

**查看執行狀況（隨時可以）：**
```bash
tmux attach -t claude
```
> 看完想離開但不要停止：按 **Ctrl + B**，然後按 **D**

---

### 起床後怎麼看結果

**快速查看（最方便）：**
```bash
# 開跑前先做健康檢查
./sleep-safe-runner.sh --doctor

# 測試通知有沒有真的送到
./sleep-safe-runner.sh --notify-test

# 看單一任務的進度、剩餘工作、最近 log
./sleep-safe-runner.sh --status 你的任務名

# 給腳本 / dashboard / 其他工具吃的 JSON 狀態
./sleep-safe-runner.sh --status-json 你的任務名

# 自動修復遺失的 task_list.md / progress.md
./sleep-safe-runner.sh --repair 你的任務名

# 列出所有任務的完成狀況
./sleep-safe-runner.sh --list
```

輸出範例：
```
📊 Status: build-auth
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Progress: 18/24 tasks (75%)

📝 Recent summary:
   Finished login and register endpoints
   Added password hashing and token generation

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

⚠️ Recent failure signal:
   [2026-04-10 03:12:09] [ERROR] Session failed (exit code: 1)

🕘 Recent session history:
   2026-04-10T03:05:22Z • session_succeeded • Finished login and register endpoints
   2026-04-10T03:48:40Z • checkpoint • Added password hashing and token generation
```

如果你想自己串通知、dashboard、外部腳本，可直接拿 JSON：
```json
{
  "version": 2,
  "task": "build-auth",
  "phase": "sleeping",
  "state": "in_progress",
  "startedAt": "2026-04-10T01:12:00Z",
  "updatedAt": "2026-04-10T03:48:53Z",
  "progress": {
    "done": 18,
    "total": 24,
    "pending": 6,
    "percent": 75
  },
  "summaryLines": [
    "Finished login and register endpoints",
    "Added password hashing and token generation"
  ],
  "failure": {
    "category": "claude_non_zero_exit",
    "summary": "Claude exited with a non-zero status.",
    "actionHint": "Inspect the latest session log under .autonomous/build-auth/logs and retry the task.",
    "signal": "[2026-04-10 03:12:09] [ERROR] Session failed (exit code: 1)"
  },
  "recentHistory": [
    {
      "timestamp": "2026-04-10T03:05:22Z",
      "phase": "session_succeeded",
      "summary": "Finished login and register endpoints"
    }
  ],
  "repairHints": [
    "Commit or stash local changes before running overnight automation."
  ]
}
```

另外，runner 現在會固定寫出：

- `.autonomous/<task>/status.json`：最新狀態 artifact
- `.autonomous/<task>/status-history.jsonl`：最近幾輪 session 歷史摘要

這兩個檔案可以直接餵給 dashboard、notification router、audit trail 或其他自動化工具。

**進一步深挖：**
```bash
# 看完整任務清單
cat .autonomous/你的任務名/task_list.md

# 看 AI 做了哪些 commit
git log --oneline -20

# 看詳細執行日誌
cat .autonomous/你的任務名/logs/runner.log
```

---

### 腳本參數調整

你可以用下列參數客製化 runner：

```bash
MAX_ITERATIONS=100           # 最大執行輪數（建議不超過 200）
MAX_CONSECUTIVE_FAILURES=5   # 連續失敗幾次才停止（timeout 不算）
MAX_SESSION_MINUTES=45       # 單輪超時（分鐘）
CHECKPOINT_EVERY=3           # 每幾輪自動 git commit
```

現在建議優先改 `.sleep-yolo.env`，這樣之後升級腳本時不用重新手改：

```bash
nano .sleep-yolo.env
```

> **Timeout vs 失敗的差別**：Claude 跑超過 45 分鐘只是「這個任務比較大」，不計入失敗次數，腳本會繼續跑。只有真正的錯誤（Claude 異常退出）才計入失敗。

---

## 📦 檔案說明

```
hans-sleep-yolo-mode/
├── README.md              # 這份說明文件
├── CLAUDE.md              # Claude 行為指引（自主決策規則）
├── sleep-safe-runner.sh   # 睡覺跑腳本（自動循環 + 通知）
├── setup-wizard.sh        # 首次設定精靈
├── .sleep-yolo.env.example # 通知與 runner 參數範本
├── install.sh             # 一鍵安裝到你的專案
├── .autonomous/<task>/status.json        # 最新任務狀態 artifact
├── .autonomous/<task>/status-history.jsonl # 最近 session 歷史摘要
├── LICENSE
└── .claude/
    ├── settings.json
    └── skills/autonomous-skill/
        └── SKILL.md       # 長時任務技能定義
```

---

## ⚠️ 安全警告！使用前必讀

> **YOLO Mode = 權限全開 = 後果自負**

這個模式會讓 Claude：
- 🔓 執行任何 bash 指令，不詢問確認
- 🔓 讀寫任何檔案
- 🔓 安裝任何套件
- 🔓 執行任何程式碼

### 安全建議

| 建議 | 原因 |
|------|------|
| **永遠在 feature branch 工作** | 出問題可以輕易還原 |
| **不要在有機密資料的專案使用** | AI 可能讀取或意外 commit 機密 |
| **建議在 VM 或 Container 中執行** | 最大程度隔離風險 |
| **確保有備份** | 以防萬一 |
| **起床後 review git log** | 確認 AI 做的事符合預期 |

### 已禁止的危險操作

CLAUDE.md 已設定禁止以下操作：

- `sudo` / `su` — 提權
- 刪除系統檔案
- commit 機密資訊（.env、API key 等）
- push 到 remote（需要人工確認）
- 對 production 資料做破壞性操作

---

## ❓ 常見問題

### Q: 我需要什麼帳號才能用？

需要 **Claude Max**（個人）或 **Claude Team**（團隊）方案，才能使用 Claude Code。

前往 [claude.ai](https://claude.ai) 升級方案。

---

### Q: 啟動後還是跳權限確認視窗？

確認用這個指令啟動：
```bash
claude --dangerously-skip-permissions
```

啟動後左下角要顯示 **`bypass permissions on`**。

如果還是會跳，按 **Shift + Tab** 切換模式直到顯示正確。

---

### Q: 睡覺跑到一半停了？

```bash
# 查看日誌
cat .autonomous/你的任務名/logs/runner.log
```

常見原因：
- Claude API 額度用完（升級方案或等次日重置）
- 網路連線中斷
- 連續失敗超過 5 次（看日誌確認原因）

如果是通知沒設定或 runner 參數不適合，可以重新跑：
```bash
./setup-wizard.sh
```

**重新啟動會從上次進度繼續（不會重頭來）：**
```bash
./sleep-safe-runner.sh "同樣的任務名稱"
```

---

### Q: 怎麼強制停止？

```bash
# 直接按 Ctrl + C

# 如果用 tmux
tmux attach -t claude
# 然後按 Ctrl + C

# 強制終止背景進程
pkill -f sleep-safe-runner
```

---

### Q: 跑完後怎麼把工作合回 main？

```bash
# 先 review 一下 AI 做了什麼
git log --oneline

# 沒問題就 merge
git checkout main
git merge auto/你的分支名稱

# 合完後刪掉功能分支，分支列表就會只剩 main
git branch -d auto/你的分支名稱
```

如果你是在 GitHub 上開 Pull Request，merge 完之後按 **Delete branch**，遠端也會只剩 `main`。

---

### Q: CLAUDE.md 和 claude --dangerously-skip-permissions 有什麼差別？

| | 作用 |
|---|---|
| `--dangerously-skip-permissions` | CLI 旗標，讓 Claude 跳過每個指令的確認彈窗 |
| `CLAUDE.md` | 提示詞，告訴 Claude 的行為準則（不問問題、自己決定等）|

兩者搭配使用效果最好。只有旗標沒有 CLAUDE.md，Claude 可能還是會問問題（透過文字）；只有 CLAUDE.md 沒有旗標，執行每個操作還是需要你按確認。

---

### Q: 這跟 Cursor / GitHub Copilot 有什麼不同？

| 工具 | 特色 |
|------|------|
| **Cursor** | IDE 整合，即時補全，需要持續互動 |
| **GitHub Copilot** | 程式碼補全為主，較少自主執行能力 |
| **Claude Code + YOLO** | 長時間自主執行完整任務，適合「睡覺跑」場景 |

---

## 🤝 貢獻

歡迎提交 Issue 和 Pull Request！

如果這個工具對你有幫助，請給個 ⭐ Star！

---

## 📄 授權

MIT License — 自由使用、修改、分享

---

## 👤 作者

**Hans Lin 林思翰**

- GitHub: [@hansai-art](https://github.com/hansai-art)

---

**Made with 💤 by Hans Lin — 讓 AI 工作，你去睡覺**
