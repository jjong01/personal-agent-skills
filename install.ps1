# 에이전트 작업 환경 설치 (Windows PowerShell 5.1+ / PowerShell 7)
# 폴더 구조, 공통 규칙(AGENTS.md) 연결, 스킬 연결. install.sh와 같은 결과를 만듦
# 사용: powershell -ExecutionPolicy Bypass -File .\install.ps1 [-DryRun]
# 파일 심볼릭 링크는 개발자 모드(설정 > 시스템 > 개발자용) 또는 관리자 권한이 필요함
# 다시 실행해도 안전함. 기존 파일·폴더는 ~\.agent-skills-backup\<시각>\ 으로 옮긴 뒤 링크함
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'

$Repo = $PSScriptRoot
$H = $HOME
$Backup = Join-Path $H ('.agent-skills-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Get-LinkTarget($path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not $item.LinkType) { return $null }
    $t = $item.Target
    if ($t -is [array]) { $t = $t[0] }
    return [string]$t
}

function Same-Path($a, $b) {
    if (-not $a -or -not $b) { return $false }
    $na = [IO.Path]::GetFullPath($a).TrimEnd('\')
    $nb = [IO.Path]::GetFullPath($b).TrimEnd('\')
    return $na -ieq $nb
}

# 링크 생성. 디렉터리는 정션(관리자 권한 불필요), 파일은 심볼릭 링크
function New-Link($src, $dest) {
    if (Same-Path (Get-LinkTarget $dest) $src) { Write-Host "ok      $dest"; return }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent)) {
        if ($DryRun) { Write-Host "[dry-run] mkdir $parent" } else { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }
    if (Test-Path -LiteralPath $dest) {
        $rel = $dest.Substring($H.Length).TrimStart('\', '/')
        $bdest = Join-Path $Backup $rel
        if ($DryRun) { Write-Host "[dry-run] backup $dest -> $bdest" }
        else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $bdest) -Force | Out-Null
            $item = Get-Item -LiteralPath $dest -Force
            if ($item.LinkType) {
                # 다른 대상을 가리키는 링크는 원본이 따로 있으므로 링크만 제거함
                $item.Delete(); Write-Host "unlink  $dest"
            } else {
                Move-Item -LiteralPath $dest -Destination $bdest; Write-Host "backup  $dest -> $bdest"
            }
        }
    }
    $isDir = (Get-Item -LiteralPath $src -Force).PSIsContainer
    if ($DryRun) { Write-Host "[dry-run] link $dest -> $src"; return }
    if ($isDir) { New-Item -ItemType Junction -Path $dest -Target $src | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path $dest -Target $src | Out-Null }
    Write-Host "linked  $dest -> $src"
}

# 파일 심볼릭 링크 생성 가능 여부를 변경 전에 확인함
function Test-SymlinkPrivilege {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('agent-link-test-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $f = Join-Path $tmp 'a.txt'; Set-Content -Path $f -Value 'x'
        New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'b.txt') -Target $f -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
    finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}

if (-not (Test-SymlinkPrivilege)) {
    Write-Host '파일 심볼릭 링크를 만들 수 없음. 아래 중 하나 후 다시 실행:' -ForegroundColor Yellow
    Write-Host '  1) 설정 > 시스템 > 개발자용 > 개발자 모드 켜기'
    Write-Host '  2) PowerShell을 관리자 권한으로 실행'
    exit 1
}

Write-Host '## 1. 폴더 구조'
foreach ($d in @("$H\dev", "$H\agent\system", "$H\agent\storage", "$H\agent\notes\handoff")) {
    if (Test-Path -LiteralPath $d) { Write-Host "ok      $d" }
    elseif ($DryRun) { Write-Host "[dry-run] mkdir $d" }
    else { New-Item -ItemType Directory -Path $d -Force | Out-Null; Write-Host "created $d" }
}

Write-Host '## 2. 공통 규칙'
New-Link (Join-Path $Repo 'global\AGENTS.md') "$H\agent\AGENTS.md"
if ($DryRun -and -not (Test-Path "$H\agent\AGENTS.md")) {
    Write-Host "[dry-run] link $H\.claude\CLAUDE.md -> $H\agent\AGENTS.md"
    Write-Host "[dry-run] link $H\.gemini\GEMINI.md -> $H\agent\AGENTS.md"
} else {
    New-Link "$H\agent\AGENTS.md" "$H\.claude\CLAUDE.md"
    New-Link "$H\agent\AGENTS.md" "$H\.gemini\GEMINI.md"
}

Write-Host '## 3. 스킬 (skills\<분류>\<이름> → 도구별 skills\<이름>)'
# 저장소에서 사라진 스킬을 가리키는 링크 정리(폴더 구조 변경·이름 변경 대비)
foreach ($dir in @("$H\.claude\skills", "$H\.gemini\config\skills")) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.LinkType } | ForEach-Object {
        $t = Get-LinkTarget $_.FullName
        if ($t -and $t.StartsWith($Repo, [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $t)) {
            if ($DryRun) { Write-Host "[dry-run] remove $($_.FullName)" } else { $_.Delete(); Write-Host "removed $($_.FullName) (대상 없음)" }
        }
    }
}
$seen = @{}
Get-ChildItem -LiteralPath (Join-Path $Repo 'skills') -Directory | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory } | ForEach-Object {
    if (-not (Test-Path (Join-Path $_.FullName 'SKILL.md'))) { return }
    if ($seen.ContainsKey($_.Name)) { Write-Host "중복 스킬 이름: $($_.Name) ($($_.FullName)) 건너뜀" -ForegroundColor Yellow; return }
    $seen[$_.Name] = $true
    New-Link $_.FullName "$H\.claude\skills\$($_.Name)"
    # .claude-only 표시가 있는 스킬은 Claude Code에만 연결함
    if (-not (Test-Path (Join-Path $_.FullName '.claude-only'))) {
        New-Link $_.FullName "$H\.gemini\config\skills\$($_.Name)"
    }
}

Write-Host '## 3-1. 공용 스크립트'
New-Link (Join-Path $Repo 'lib') "$H\agent\lib"

Write-Host '## 4. 서브에이전트 (Claude Code 전용)'
$agentsDir = Join-Path $Repo 'agents'
if (Test-Path -LiteralPath $agentsDir) {
    Get-ChildItem -LiteralPath $agentsDir -Filter '*.md' -File | ForEach-Object {
        New-Link $_.FullName "$H\.claude\agents\$($_.Name)"
    }
}

Write-Host '## 5. 설정 병합 (저장소 settings\ → 기기 설정, 기존 값 유지)'
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) { Write-Host 'python 없음: 설정 병합 건너뜀' }
else {
    $merge = Join-Path $Repo 'lib\merge-settings.py'
    $pairs = @(
        @((Join-Path $Repo 'settings\claude.json'), "$H\.claude\settings.json"),
        @((Join-Path $Repo 'settings\agy.json'), "$H\.gemini\antigravity-cli\settings.json")
    )
    foreach ($p in $pairs) {
        $a = @('-I', $merge, $p[0], $p[1])
        if ($DryRun) { $a += '--dry-run' }
        & $py.Source @a
    }
}

Write-Host '## 6. 도구 확인'
$hints = [ordered]@{
    'claude' = 'https://docs.claude.com/claude-code 설치 안내 참고'
    'agy'    = 'Antigravity CLI 설치 안내 참고'
    'git'    = 'winget install Git.Git   # Claude Code가 Git Bash로 명령을 실행함'
    'node'   = 'winget install OpenJS.NodeJS.LTS'
    'python' = 'winget install Python.Python.3.12   # lib\run-agy.sh(delegate·image-edit·offload)에 필요'
    'rg'     = 'winget install BurntSushi.ripgrep.MSVC'
    'fd'     = 'winget install sharkdp.fd'
    'bat'    = 'winget install sharkdp.bat'
    'delta'  = 'winget install dandavison.delta'
}
$missing = @($hints.Keys | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($missing.Count -gt 0) {
    Write-Host "없음: $($missing -join ', ')"
    foreach ($m in $missing) { Write-Host "  $m : $($hints[$m])" }
} else {
    Write-Host 'ok      필요한 도구 모두 있음'
}

Write-Host '## 7. 점검'
$broken = @()
$checks = @("$H\agent\AGENTS.md", "$H\agent\lib", "$H\.claude\CLAUDE.md", "$H\.gemini\GEMINI.md")
foreach ($dir in @("$H\.claude\skills", "$H\.gemini\config\skills", "$H\.claude\agents")) {
    if (Test-Path -LiteralPath $dir) { $checks += @(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object { $_.FullName }) }
}
foreach ($c in $checks) {
    $t = Get-LinkTarget $c
    if ($t -and -not (Test-Path -LiteralPath $t)) { $broken += $c }
}
if ($broken.Count -gt 0) { $broken | ForEach-Object { Write-Host "깨진 링크: $_" } } else { Write-Host 'ok      링크 정상' }
if (Get-Command agy -ErrorAction SilentlyContinue) {
    $m = (& agy models 2>$null) -join "`n"
    if ($m -match 'gemini') { Write-Host 'ok      agy 모델 목록 조회됨(로그인 상태)' }
    else { Write-Host '확인 필요: agy models 실패. agy를 한 번 실행해 로그인' }
} else { Write-Host '확인 필요: agy 없음. delegate·offload·image-edit는 agy가 있어야 위임함' }
if ($py) {
    & $py.Source -c 'import PIL' 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host 'ok      python·PIL' } else { Write-Host '참고: PIL 없음(image-edit만 필요): pip install pillow' }
} else { Write-Host '확인 필요: python 없음(run-agy.sh·설정 병합에 필요)' }
$plug = Join-Path $H '.claude\plugins'
if ((Test-Path -LiteralPath $plug) -and (Get-ChildItem -LiteralPath $plug -Recurse -Depth 3 -Directory -Filter 'context-mode*' -ErrorAction SilentlyContinue)) {
    Write-Host 'ok      context-mode 플러그인'
} else { Write-Host '확인 필요: Claude Code에서 /plugin install context-mode@context-mode 실행' }
