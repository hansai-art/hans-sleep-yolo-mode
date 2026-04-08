# 🚀 Hans Sleep YOLO Mode

> **啟動指令：** `claude --dangerously-skip-permissions`
> 
> **快捷 alias：** 在終端機執行一次 `echo 'alias yolo="claude --dangerously-skip-permissions"' >> ~/.zshrc && source ~/.zshrc`，之後只要打 `yolo` 即可

---

## ⚡ Prime Directives（絕對遵守）

1. **NEVER ask questions** — 自己做決定，不要問
2. **NEVER wait for confirmation** — 直接執行，不要等
3. **NEVER stop on errors** — 遇到錯誤自己修，繼續往下
4. **NEVER leave tasks incomplete** — 做完才停
5. **ALWAYS commit after changes** — 改完就 commit
6. **ALWAYS test before marking done** — 測試通過才算完成

---

## 🎯 Decision Framework

遇到不確定的情況：

| 狀況 | 行動 |
|------|------|
| 多種解法？ | 選最簡單的 |
| 缺少資訊？ | 用合理預設值 |
| 需求衝突？ | 照 codebase 現有 pattern |
| 卡住了？ | 記錄問題，跳過，繼續下一個 |
| 外部依賴壞了？ | Mock 掉，繼續開發 |
| 測試失敗？ | 讀錯誤訊息，修到過，再繼續 |
| 型別錯誤 / lint 警告？ | 修掉，不要用 any 或 ignore 矇混 |
| 需要新的套件？ | 直接安裝，不要問 |
| 不知道正確做法？ | 搜尋 codebase 找類似 pattern，照著做 |
| 有多個 TODO 項目？ | 照順序，一次做一個，做完才做下一個 |

---

## 🛠 Tech Stack（依專案調整）

```yaml
Runtime: Node 20 LTS / Python 3.11+
Package: pnpm / npm / yarn / bun / uv
Framework: 依專案（React, Next.js, Vue, FastAPI, etc.）
Testing: 依專案（vitest, jest, pytest, etc.）
```

---

## 📝 Common Commands

```bash
# Node.js
pnpm install && pnpm dev
pnpm build && pnpm test

# Python
uv sync && uv run python main.py
uv run pytest

# Git
git add -A && git commit -m "feat: description"
```

---

## 🔄 Git Workflow

- 在 feature branch 工作：`git checkout -b feature/task-name`
- 頻繁小 commit：`git commit -m "feat: add login"`
- Conventional commits：`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- **❌ 不要 push** — 人工 review 後再 push

---

## 📦 Long-Running Tasks（自主執行模式）

複雜任務使用 autonomous skill：

```
觸發詞：「autonomous」「自主執行」「long-running task」
儲存位置：.autonomous/<task-name>/
進度追蹤：task_list.md（用 - [ ] / - [x] checkbox）
```

---

## 🚫 Safety Boundaries

- ❌ 不執行 `sudo` / `su`
- ❌ 不刪除系統檔案
- ❌ 不 commit 機密資訊（.env、API key、token 等）
- ❌ 不 push 到 remote
- ❌ 不對 production 資料做破壞性操作
- ❌ 不修改 CI/CD pipeline（除非任務明確要求）

---

## 🔧 Error Recovery

錯誤處理流程：

1. 讀完整錯誤訊息（不要只看最後一行）
2. 搜尋 codebase 找類似 pattern
3. 試最常見的修法
4. 同樣方式失敗 3 次 → 換不同方法
5. 3 種方法都失敗 → 記錄問題，跳過，繼續下一個
6. 永不放棄 — 記錄並繼續，不要停在那裡

### 常見錯誤處理

| 錯誤類型 | 處理方式 |
|---------|---------|
| `Module not found` | 先安裝缺少的套件 |
| `Type error` | 修正型別，不用 `any` 矇混 |
| `Test failed` | 讀測試內容，修到通過 |
| `Port already in use` | 用不同 port 或 kill 佔用的 process |
| `Permission denied` | 檢查檔案權限，用 chmod 修正 |
| `API rate limit` | 加 retry + backoff 邏輯 |
| `Build failed` | 讀完整 build log，從第一個錯誤開始修 |

---

## 📱 通知設定

睡覺跑時會發送通知：

```
🚀 Started — 開始執行
📊 Checkpoint — 進度報告
🎉 Completed — 全部完成
🔴 Failed — 連續失敗停止
🛑 Stopped — 手動停止
```

通知設定方式見 README.md 的「路徑 D」章節。

---

## 🌙 Sleep Mode 使用方式

```bash
# 1. 建立專用分支
git checkout -b auto/my-feature

# 2. 啟動
./sleep-safe-runner.sh "build-my-feature"

# 3. 去睡覺 💤
```

---

**Made for Hans Lin @ Group.G** 🎬
