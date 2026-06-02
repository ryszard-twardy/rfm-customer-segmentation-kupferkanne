#requires -Version 7
# Git hygiene check - SessionStart hook for Kupferkanne (READ-ONLY, INFORMATIONAL).
# Reports working-tree + remote-sync state and renders a banner via systemMessage.
# It NEVER commits, stashes, pulls, or proposes git mutations - it only reports.
# Priority signal: warn when the LOCAL checkout is BEHIND origin (a newer version
# exists on the remote, likely pushed from the other machine).

$ErrorActionPreference = 'SilentlyContinue'
$env:GIT_TERMINAL_PROMPT = '0'   # never block on a credential prompt

# Locate repo root from this script's own location (.claude/hooks -> repo root),
# so internal git operations work regardless of the hook's working directory.
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repo

function Emit {
    param([string]$Context, [string]$SysMsg)
    $obj = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'SessionStart'
            additionalContext = $Context
        }
    }
    if ($SysMsg) { $obj['systemMessage'] = $SysMsg }
    $obj | ConvertTo-Json -Depth 6 -Compress
}

$inside = (git rev-parse --is-inside-work-tree 2>$null)
if ($inside -ne 'true') {
    Emit -Context 'git-hygiene: not a git work tree; check skipped.' -SysMsg 'Git hygiene: not a git work tree.'
    exit 0
}

$branch     = (git rev-parse --abbrev-ref HEAD 2>$null)
$porcelain  = git status --porcelain 2>$null
$dirtyCount = (($porcelain | Measure-Object -Line).Lines)
$isDirty    = [bool]$porcelain

# Best-effort, time-boxed fetch so a slow/offline remote never hangs the session.
$fetchOk = $false
$job = Start-Job { $env:GIT_TERMINAL_PROMPT = '0'; git -C $using:repo fetch --quiet 2>&1 | Out-Null }
if (Wait-Job $job -Timeout 8) { $fetchOk = $true }
Remove-Job $job -Force 2>$null

$behind = 0; $ahead = 0; $haveUpstream = $false
$counts = (git rev-list --left-right --count "origin/$branch...HEAD" 2>$null)
if ($LASTEXITCODE -eq 0 -and $counts -match '^\d+\s+\d+$') {
    $haveUpstream = $true
    $parts  = ($counts.Trim() -split '\s+')
    $behind = [int]$parts[0]
    $ahead  = [int]$parts[1]
}

# Agent-facing context: STATE ONLY, no action directives (operator decides).
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('=== Git hygiene (read-only status; no action taken) ===')
$lines.Add("Branch: $branch")
if ($isDirty) { $lines.Add("Working tree DIRTY: $dirtyCount uncommitted/untracked path(s) - machine-local.") }
else          { $lines.Add('Working tree clean.') }
if (-not $fetchOk)          { $lines.Add('Remote: fetch timed out/offline - sync with origin NOT verified.') }
elseif (-not $haveUpstream) { $lines.Add("Remote: no upstream for origin/$branch.") }
else {
    if ($behind -gt 0) { $lines.Add("STALE: local is BEHIND origin/$branch by $behind commit(s) - a newer version exists on the remote (likely pushed from the other machine).") }
    if ($ahead  -gt 0) { $lines.Add("Ahead of origin/$branch by $ahead commit(s) - unpushed (machine-local).") }
    if ($behind -eq 0 -and $ahead -eq 0) { $lines.Add("In sync with origin/$branch.") }
}
$lines.Add('Operator decides any commit/pull; the hook itself changes nothing.')
$context = ($lines -join "`n")

# User-facing banner. Priority: STALE > dirty > clean.
if ($fetchOk -and $haveUpstream -and $behind -gt 0) {
    $extra = if ($isDirty) { " + $dirtyCount uncommitted" } else { '' }
    $sys = "Git hygiene: STALE - $branch is BEHIND origin by $behind (newer version on remote)$extra."
}
elseif ($isDirty) {
    $sys = "Git hygiene: $branch has $dirtyCount uncommitted path(s) - machine-local, not yet pushed."
}
elseif (-not $fetchOk) {
    $sys = "Git hygiene: $branch clean (local) - REMOTE NOT CHECKED, staleness unknown."
}
else {
    if (-not $haveUpstream) { $remote = 'no upstream' }
    elseif ($ahead -gt 0)   { $remote = "ahead by $ahead (unpushed)" }
    else                    { $remote = 'in sync' }
    $sys = "Git hygiene OK: $branch clean, $remote."
}

Emit -Context $context -SysMsg $sys
exit 0
