# .claude/hooks/git-state-check.ps1
# SessionStart read-only git-state check. Reports dirty / ahead / behind. NEVER acts.
$ErrorActionPreference = 'SilentlyContinue'
if ((git rev-parse --is-inside-work-tree 2>$null) -ne 'true') { exit 0 }
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
$dirty = git status --porcelain 2>$null
$dirtyCount = if ($dirty) { ($dirty | Measure-Object -Line).Lines } else { 0 }
$env:GIT_HTTP_LOW_SPEED_LIMIT = '1000'
$env:GIT_HTTP_LOW_SPEED_TIME  = '5'
git fetch --quiet 2>$null
$upstream = (git rev-parse --abbrev-ref '@{u}' 2>$null)
if ($upstream) {
    $counts = (git rev-list --left-right --count "$upstream...HEAD" 2>$null) -split '\s+'
    if ($counts.Count -ge 2 -and $counts[0] -match '^\d+$' -and $counts[1] -match '^\d+$') {
        $behind = [int]$counts[0]; $ahead = [int]$counts[1]
    } else { $upstream = $null }   # comparison unavailable -> falls to "no upstream" report, exit 0 preserved
}
Write-Host "-- git state [$branch] --"
if ($dirtyCount -gt 0) { Write-Host "  UNCOMMITTED: $dirtyCount file(s) - commit before switching machines" }
else { Write-Host "  working tree clean" }
if (-not $upstream) { Write-Host "  no upstream set (cannot compare to remote)" }
elseif ($ahead -gt 0 -and $behind -gt 0) { Write-Host "  DIVERGED: $ahead ahead / $behind behind - reconcile before pushing" }
elseif ($behind -gt 0) { Write-Host "  BEHIND by $behind - run git pull before working" }
elseif ($ahead -gt 0) { Write-Host "  AHEAD by $ahead - unpushed commits" }
else { Write-Host "  in sync with $upstream" }
exit 0
