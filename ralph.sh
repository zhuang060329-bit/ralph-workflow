#!/usr/bin/env bash
# 外層 Ralph 迴圈 — 無人值守開發驅動腳本(macOS / Linux 版,與 ralph.ps1 等價)
# 用法: ./ralph.sh [最大輪次] [花費上限USD]

set -uo pipefail

MAX_ROUNDS="${1:-200}"
MAX_COST="${2:-50}"
SLEEP_SECONDS=5

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR" || exit 1

# --- 前置檢查 -----------------------------------------------------------
[ -f PROMPT.md ] || { echo "找不到 PROMPT.md,中止。"; exit 1; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "ralph-auto" ]; then
  echo "目前分支為 '$BRANCH',本迴圈只允許在 'ralph-auto' 分支執行。"
  echo "請先執行:git checkout ralph-auto"
  exit 1
fi

if [ -f .ralph-stop ]; then
  echo ".ralph-stop 已存在(上次已完工)。若要重跑請先刪除該檔案。"
  exit 0
fi

# --- 主迴圈 -------------------------------------------------------------
mkdir -p logs
RUN_LOG="logs/ralph-run-$(date +%Y%m%d-%H%M%S).log"
round=0
total_cost=0
stop_reason=""

echo "Ralph 迴圈啟動 | 分支: $BRANCH | 輪次上限: $MAX_ROUNDS | 花費上限: \$$MAX_COST"

while true; do
  [ -f .ralph-stop ] && { stop_reason="COMPLETED"; break; }
  [ "$round" -ge "$MAX_ROUNDS" ] && { stop_reason="MAX_ROUNDS"; break; }
  # 浮點比較需用 awk
  if awk -v a="$total_cost" -v b="$MAX_COST" 'BEGIN{exit !(a>=b)}'; then
    stop_reason="MAX_COST"; break
  fi

  round=$((round + 1))
  echo ""
  echo "=== 第 $round 輪 | 累計花費 \$$total_cost ==="

  # 每輪全新 process:不帶 --continue / --resume,context 完全歸零
  raw="$(claude -p "$(cat PROMPT.md)" --output-format json --dangerously-skip-permissions)"

  {
    echo "===== ROUND $round ====="
    echo "$raw"
  } >> "$RUN_LOG"

  # 取本輪花費(欄位缺失時降級處理,不中斷迴圈)
  cost="$(echo "$raw" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("total_cost_usd") or 0)' 2>/dev/null || echo 0)"
  total_cost="$(awk -v a="$total_cost" -v b="$cost" 'BEGIN{printf "%.4f", a+b}')"

  sleep "$SLEEP_SECONDS"
done

# --- 收尾與通知 ---------------------------------------------------------
SUMMARY="Ralph 迴圈結束 | 原因: $stop_reason | 共 $round 輪 | 累計花費: \$$total_cost"
echo "$SUMMARY" >> "$RUN_LOG"

if [ "$stop_reason" = "COMPLETED" ]; then
  echo ""
  echo "$SUMMARY"
  echo "所有任務完成。請人工 review 分支 diff 後,再自行決定是否 merge / push。"
else
  if [ "$stop_reason" = "MAX_ROUNDS" ]; then
    REASON_TEXT="達到輪次上限仍未完工"
  else
    REASON_TEXT="達到花費上限仍未完工"
  fi
  cat >> NEEDS_HUMAN.md <<EOF

## $(date '+%Y-%m-%d %H:%M') — 迴圈非正常結束
- 原因:${REASON_TEXT}(${stop_reason})
- 已執行輪次:${round}
- 累計花費:\$${total_cost}
- 請檢查:TASKS.md 卡在哪一項、PROGRESS.md 最後數行、${RUN_LOG}
EOF
  echo ""
  echo "$SUMMARY"
  echo "${REASON_TEXT},已寫入 NEEDS_HUMAN.md。"
  # 終端鐘聲通知(響三聲)
  for _ in 1 2 3; do printf '\a'; sleep 0.2; done
fi
