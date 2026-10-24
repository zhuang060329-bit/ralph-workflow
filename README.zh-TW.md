# ralph-workflow

[English](README.md) | 繁體中文

> **已封存（2026-10）。** 這個骨架只完成初始化，沒有實際跑完過一個任務，之後不再維護。
>
> **已知問題：在 macOS / Linux 上，守門 hook 很可能不會生效。** `.claude/settings.json` 用 `powershell` 呼叫 `guard.ps1`。macOS 與 Linux 通常沒有叫做 `powershell` 的指令（Homebrew 裝的 PowerShell 叫 `pwsh`），指令啟動失敗時 Claude Code 把它當成非阻擋錯誤，工具照常執行。`ralph.sh` 又帶 `--dangerously-skip-permissions`，所以下方「安全邊界」列的攔截在這兩個平台上不成立。這是依 Claude Code hook 的結束碼規則推論，沒有在 macOS 上實測。參考這個 repo 時，請先把 hook 改成跨平台的實作。

無人值守開發工作流。外層 Ralph 迴圈驅動,內層視任務性質呼叫 subagent 或 Agent Team。

## 架構

```
外層迴圈(ralph.ps1 / ralph.sh,唯一持續運行的東西)
  └─ 每輪:全新 claude -p process,context 歸零
       ├─ 讀 TASKS.md + PROGRESS.md 尾段 + git log 還原現況
       ├─ 選一個任務 → 三選一執行:
       │    · 單一低歧義 → 主 agent 自己做
       │    · 獨立模組 / 修 bug → 一次性 subagent
       │    · 多角度交叉驗證 → 短暫 Agent Team(2–4 人)
       ├─ 獨立 agent 審查 → 只讀第一行「### 判定：PASS / FAIL」
       │    · FAIL → 新 subagent 修復(附報告+diff)→ 重審(本輪內小迴圈,上限 3 次)
       ├─ 更新 TASKS.md + 附加 PROGRESS.md + git commit
       └─ 全部完成 → 建立 .ralph-stop 收工
```

## 檔案

| 檔案 | 用途 |
|---|---|
| `PROMPT.md` | 每輪固定餵給 Claude 的提示詞(工作流的真正核心) |
| `TASKS.md` | 任務清單。`[ ]` 待處理 / `[~]` 進行中 / `[x]` 完成 / `[!]` 卡住 |
| `PROGRESS.md` | append-only 執行日誌 |
| `NEEDS_HUMAN.md` | 卡住或異常結束時自動產生,需要人工介入 |
| `.ralph-stop` | 完工 sentinel,出現即停止迴圈 |
| `ralph.ps1` / `ralph.sh` | 外層迴圈(Windows / macOS-Linux) |
| `.claude/hooks/guard.ps1` | PreToolUse 守門,攔截危險指令 |
| `logs/` | 每次執行的完整 JSON 輸出 |

## 使用步驟

1. **填任務**:編輯 `TASKS.md`,把範例任務換成真實任務(建議第一項就是「決定技術棧並初始化骨架」)。
2. **切分支**:`git checkout ralph-auto`(迴圈拒絕在其他分支執行)。
3. **啟動**:
   ```powershell
   .\ralph.ps1 -MaxRounds 50 -MaxCostUsd 20
   ```
   建議首次跑先設小上限觀察行為,確認正常後再放大。
4. **結束後**:人工 review `ralph-auto` 分支的完整 diff,自行決定是否 merge 或 push。
   迴圈本身**不會**自動 push / merge。

## 安全邊界

- 只在 `ralph-auto` 分支工作,不碰 main。
- 不自動 push / merge(不可逆操作留給人工)。
- `guard.ps1` 攔截 `git push`、`git reset --hard`、`rm -rf`、跨目錄操作等。
- 雙重停止條件:`.ralph-stop`(正常完工)+ 輪次上限 + 花費上限(防失控)。
- 異常結束會寫 `NEEDS_HUMAN.md` 並發終端鐘聲。

## 已知限制

- Agent Teams 為實驗性功能,需 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`(已寫入 `.claude/settings.json`)。
  官方文件本身不建議 Agent Teams 長時間無人值守,因此本架構只在需要多角度驗證時短暫使用,
  由外層 Ralph 迴圈承擔無人值守的職責。
- 每輪 context 歸零是刻意設計:換來的代價是無法 resume 上一輪的 subagent,
  因此修 bug 採「新 subagent + 完整上下文」而非「原 agent 續談」。
