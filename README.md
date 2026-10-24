# ralph-workflow

English | [繁體中文](README.zh-TW.md)

> **Archived (October 2026).** This skeleton was initialized but never completed a real task run. It is no longer maintained.
>
> **Known issue: on macOS and Linux the safety hook most likely does nothing.** `.claude/settings.json` runs `guard.ps1` through a command named `powershell`. macOS and Linux usually have no such command (Homebrew installs PowerShell as `pwsh`), and Claude Code treats a hook that fails to start as a non-blocking error, so the tool call goes ahead. `ralph.sh` also passes `--dangerously-skip-permissions`. The blocklist described under "Safety boundaries" therefore does not hold on those platforms. This conclusion comes from Claude Code's documented hook exit-code rules; it was not tested on a Mac. Replace the hook with a cross-platform script before reusing anything here.

A skeleton for unattended development with Claude Code. An outer "Ralph" loop starts a fresh `claude -p` process every round; inside a round the agent either does the task itself, hands it to a one-off subagent, or spins up a short-lived Agent Team for cross-checking.

## How a round works

```
Outer loop (ralph.ps1 / ralph.sh — the only long-running process)
  └─ each round: a new `claude -p` process, empty context
       ├─ rebuild state from TASKS.md, the tail of PROGRESS.md and git log
       ├─ pick one task and run it one of three ways:
       │    · single, unambiguous task  → main agent
       │    · isolated module / bug fix → one-off subagent
       │    · needs several viewpoints  → short-lived Agent Team (2–4)
       ├─ an independent agent reviews; only the first line is read:
       │    "### 判定：PASS / FAIL"
       │    · FAIL → new subagent fixes it (given report + diff) → re-review, max 3 times
       ├─ update TASKS.md, append to PROGRESS.md, git commit
       └─ all tasks done → create .ralph-stop
```

## Files

| File | Purpose |
|---|---|
| `PROMPT.md` | The prompt fed to Claude every round — the actual core of the workflow |
| `TASKS.md` | Task list. `[ ]` todo / `[~]` in progress / `[x]` done / `[!]` blocked |
| `PROGRESS.md` | Append-only run log |
| `NEEDS_HUMAN.md` | Written when the loop stops abnormally |
| `.ralph-stop` | Completion sentinel; the loop exits when it exists |
| `ralph.ps1` / `ralph.sh` | Outer loop for Windows / macOS and Linux |
| `.claude/hooks/guard.ps1` | PreToolUse hook that blocks dangerous commands (Windows only in practice, see above) |
| `logs/` | Full JSON output of every round (created at run time) |

## Usage

1. Replace the sample tasks in `TASKS.md` with real ones.
2. `git checkout ralph-auto` — the loop refuses to run on any other branch.
3. Start it with a small budget first:
   ```powershell
   .\ralph.ps1 -MaxRounds 50 -MaxCostUsd 20
   ```
4. Review the full diff of `ralph-auto` yourself. The loop never pushes or merges.

## Safety boundaries (as designed)

- Works only on the `ralph-auto` branch.
- Never pushes or merges; irreversible steps are left to a human.
- `guard.ps1` blocks `git push`, `git reset --hard`, `rm -rf`, operations outside the project, and similar commands.
- Two stop conditions: `.ralph-stop` for normal completion, plus round and cost limits.
- An abnormal stop writes `NEEDS_HUMAN.md` and rings the terminal bell.

## Limits

- Agent Teams is experimental and needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (set in `.claude/settings.json`). Its documentation advises against long unattended runs, so this design uses teams only briefly and leaves the unattended part to the outer loop.
- Every round starts with empty context on purpose. The cost is that a subagent from an earlier round cannot be resumed, so fixes always go to a new subagent with full context.
