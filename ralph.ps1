# 外層 Ralph 迴圈 — 無人值守開發驅動腳本
# 用法:  .\ralph.ps1              使用預設上限
#        .\ralph.ps1 -MaxRounds 50 -MaxCostUsd 20
#
# 設計原則:每輪都是全新的 claude process,context 完全歸零,
#          狀態全靠 TASKS.md / PROGRESS.md / git commit 維持。

param(
    [int]$MaxRounds = 200,        # 輪次上限(防無限迴圈)
    [double]$MaxCostUsd = 50.0,  # 花費上限 USD(防失控燒錢)
    [int]$SleepSeconds = 5        # 每輪間隔
)

$ErrorActionPreference = "Stop"
$ProjectDir = $PSScriptRoot
Set-Location $ProjectDir

# --- 前置檢查 -----------------------------------------------------------
if (-not (Test-Path (Join-Path $ProjectDir "PROMPT.md"))) {
    Write-Host "找不到 PROMPT.md,中止。" -ForegroundColor Red
    exit 1
}

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne "ralph-auto") {
    Write-Host "目前分支為 '$branch',本迴圈只允許在 'ralph-auto' 分支執行。" -ForegroundColor Red
    Write-Host "請先執行:git checkout ralph-auto" -ForegroundColor Yellow
    exit 1
}

if (Test-Path (Join-Path $ProjectDir ".ralph-stop")) {
    Write-Host ".ralph-stop 已存在(上次已完工)。若要重跑請先刪除該檔案。" -ForegroundColor Yellow
    exit 0
}

# --- 主迴圈 -------------------------------------------------------------
$prompt = Get-Content (Join-Path $ProjectDir "PROMPT.md") -Raw -Encoding UTF8
$round = 0
$totalCost = 0.0
$stopReason = ""
$runLog = Join-Path $ProjectDir "logs\ralph-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

Write-Host "Ralph 迴圈啟動 | 分支: $branch | 輪次上限: $MaxRounds | 花費上限: `$$MaxCostUsd" -ForegroundColor Cyan

while ($true) {

    if (Test-Path (Join-Path $ProjectDir ".ralph-stop")) { $stopReason = "COMPLETED"; break }
    if ($round -ge $MaxRounds)                           { $stopReason = "MAX_ROUNDS"; break }
    if ($totalCost -ge $MaxCostUsd)                      { $stopReason = "MAX_COST";   break }

    $round++
    Write-Host "`n=== 第 $round 輪 | 累計花費 `$$([math]::Round($totalCost,4)) ===" -ForegroundColor Cyan

    # 每輪全新 process:不帶 --continue / --resume,context 完全歸零
    $raw = $prompt | claude -p --output-format json --dangerously-skip-permissions

    Add-Content -Path $runLog -Value "===== ROUND $round =====" -Encoding utf8
    Add-Content -Path $runLog -Value $raw -Encoding utf8

    # 取本輪花費(欄位缺失時降級處理,不中斷迴圈)
    try {
        $result = $raw | ConvertFrom-Json
        if ($null -ne $result.total_cost_usd) {
            $totalCost += [double]$result.total_cost_usd
        }
    } catch {
        Write-Host "本輪 JSON 解析失敗,花費未計入(詳見 $runLog)" -ForegroundColor Yellow
    }

    Start-Sleep -Seconds $SleepSeconds
}

# --- 收尾與通知 ---------------------------------------------------------
$summary = "Ralph 迴圈結束 | 原因: $stopReason | 共 $round 輪 | 累計花費: `$$([math]::Round($totalCost,4))"
Add-Content -Path $runLog -Value $summary -Encoding utf8

if ($stopReason -eq "COMPLETED") {
    Write-Host "`n$summary" -ForegroundColor Green
    Write-Host "所有任務完成。請人工 review 分支 diff 後,再自行決定是否 merge / push。" -ForegroundColor Green
} else {
    $reasonText = if ($stopReason -eq "MAX_ROUNDS") { "達到輪次上限仍未完工" } else { "達到花費上限仍未完工" }
    $needsHuman = Join-Path $ProjectDir "NEEDS_HUMAN.md"
    Add-Content -Path $needsHuman -Encoding utf8 -Value @"

## $(Get-Date -Format 'yyyy-MM-dd HH:mm') — 迴圈非正常結束
- 原因:$reasonText($stopReason)
- 已執行輪次:$round
- 累計花費:`$$([math]::Round($totalCost,4))
- 請檢查:TASKS.md 卡在哪一項、PROGRESS.md 最後數行、$runLog
"@
    Write-Host "`n$summary" -ForegroundColor Red
    Write-Host "$reasonText,已寫入 NEEDS_HUMAN.md。" -ForegroundColor Red
    # 終端鐘聲通知(響三聲)
    1..3 | ForEach-Object { [Console]::Beep(880, 200); Start-Sleep -Milliseconds 150 }
}
