# ralph-workflow 專案規則

## 定位
無人值守開發工作流的實驗與執行專案。外層 Ralph 迴圈驅動,內層視需要呼叫
subagent 或 Agent Team。技術棧尚未鎖定。

## 邊界(硬性)
- 本專案是獨立 git repo,工作分支固定為 `ralph-auto`。
- **禁止**操作 `D:\ClaudeCode` 根目錄、`KnowledgeBase\`、以及其他子專案。
- **禁止** `git push`、`git merge`、`git reset --hard`、`git push --force`。
  這些不可逆操作一律留給人工。
- 迴圈只在本專案目錄內讀寫檔案。

## 工作流規則
執行細節以 `PROMPT.md` 為準。核心不可違反的三條:
1. 每輪都是全新 process,記憶只存在於 `TASKS.md` / `PROGRESS.md` / git log。
2. 寫程式的 agent 不得審查自己的成果,一律由獨立 agent 審查。
3. 修 bug 開全新 subagent 並附完整上下文,不嘗試 resume 舊 agent。

## 語言
所有輸出、commit message、程式碼註解一律使用繁體中文。
