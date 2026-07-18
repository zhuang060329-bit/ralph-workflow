# PreToolUse 守門 hook — 攔截無人值守情況下的危險指令
# 輸入:Claude Code 由 stdin 傳入 JSON,含 tool_name 與 tool_input.command
# 輸出:exit 0 放行;exit 2 阻擋(stderr 內容會回饋給 agent)

$ErrorActionPreference = "Stop"

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    # 解析失敗時放行,避免 hook 本身成為單點故障
    exit 0
}

$cmd = ""
if ($null -ne $payload.tool_input) {
    if ($null -ne $payload.tool_input.command) { $cmd = [string]$payload.tool_input.command }
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# 攔截規則:每項為「正則, 阻擋原因」
$rules = @(
    @{ p = 'git\s+push';                          r = 'git push 為不可逆的對外操作,無人值守迴圈禁止執行,請留給人工決定。' },
    @{ p = 'git\s+merge';                         r = 'git merge 禁止由迴圈自動執行,請人工 review diff 後再合併。' },
    @{ p = 'git\s+reset\s+--hard';                r = 'git reset --hard 會丟棄未提交的工作,禁止執行。' },
    @{ p = 'git\s+clean\s+-[a-zA-Z]*f';           r = 'git clean -f 會刪除未追蹤檔案,禁止執行。' },
    @{ p = 'git\s+(checkout|switch)\s+(main|master)'; r = '本迴圈只允許在 ralph-auto 分支工作,禁止切換到 main/master。' },
    @{ p = 'git\s+branch\s+-D';                   r = '強制刪除分支為不可逆操作,禁止執行。' },
    @{ p = 'git\s+init';                          r = 'git init 禁止由迴圈執行(尤其禁止在工作區根目錄)。' },
    @{ p = 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f';          r = 'rm -rf 禁止在無人值守迴圈中執行。' },
    @{ p = 'Remove-Item.*-Recurse.*-Force';       r = 'Remove-Item -Recurse -Force 禁止在無人值守迴圈中執行。' },
    @{ p = 'D:\\ClaudeCode\\KnowledgeBase';       r = '禁止碰觸 KnowledgeBase 目錄。' },
    @{ p = 'D:\\ClaudeCode\\projects\\(?!ralph-workflow)'; r = '禁止操作其他子專案目錄,本迴圈僅限 ralph-workflow。' },
    @{ p = 'D:\\ClaudeCode\\(CLAUDE\.md|WORKSPACE_STATE\.md|\.claude)'; r = '禁止修改工作區根目錄的規則與設定檔。' }
)

foreach ($rule in $rules) {
    if ($cmd -match $rule.p) {
        [Console]::Error.WriteLine("【guard hook 阻擋】$($rule.r)")
        [Console]::Error.WriteLine("被阻擋的指令:$cmd")
        exit 2
    }
}

exit 0
