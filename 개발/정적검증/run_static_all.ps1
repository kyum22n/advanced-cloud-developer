<#  개발/ 전체 정적 검증 — 1차(도구 무관) + 2차(도구별)
    실행: pwsh -File .\run_static_all.ps1 [-SkipInstall]

    설계 근거: 설계/공통/06_테스트설계서.md — 정적 검증은 «가장 싼 레벨»이다.
    여기서 잡히는 결함은 빌드·배포·테스트로 갈수록 발견 비용이 커진다.
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$ContinueOnError
)

$ErrorActionPreference = 'Continue'
# 한글 출력이 리다이렉트될 때 인코딩 오류로 종료 코드가 오염되는 것을 막는다
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = (Resolve-Path "$PSScriptRoot\..").Path
$reportDir = "$PSScriptRoot\reports"
New-Item -ItemType Directory -Force $reportDir | Out-Null
$results = @()

function Add-R {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:results += [ordered]@{ Name = $Name; Status = $(if ($Ok) { 'Pass' } else { 'Fail' }); Detail = $Detail }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    $mark = if ($Ok) { '[PASS]' } else { '[FAIL]' }
    Write-Host ("{0} {1} {2}" -f $mark, $Name, $Detail) -ForegroundColor $color
}

function Invoke-Step {
    param([string]$Name, [string]$WorkDir, [scriptblock]$Script)
    if (-not (Test-Path $WorkDir)) { Add-R $Name $false '경로 없음'; return }
    Push-Location $WorkDir
    try {
        & $Script *>&1 | Out-String | Write-Verbose
        Add-R $Name ($LASTEXITCODE -eq 0) ("exit=" + $LASTEXITCODE)
    } catch {
        Add-R $Name $false $_.Exception.Message
    } finally {
        Pop-Location
    }
}

Write-Host "`n=== 1차: 도구 설치 없이 항상 실행되는 검사 ===" -ForegroundColor Cyan
Push-Location $PSScriptRoot
python .\verify_static.py
Add-R '1차 정적 검증(verify_static.py)' ($LASTEXITCODE -eq 0) ''
Pop-Location

Write-Host "`n=== 2차: 언어별 정적 분석 도구 ===" -ForegroundColor Cyan

# ── Java (Spring Boot) — Checkstyle · SpotBugs ──
$sb = "$root\backend\springboot"
if (Test-Path "$sb\pom.xml") {
    if (-not $env:JAVA_HOME) { Write-Host '  [INFO] JAVA_HOME 미설정 — Java 검증을 건너뜁니다.' -ForegroundColor Yellow }
    else {
        Invoke-Step 'Java Checkstyle' $sb { mvn -B -q checkstyle:check }
        Invoke-Step 'Java 컴파일'      $sb { mvn -B -q -DskipTests compile }
        Invoke-Step 'Java 단위 테스트'  $sb { mvn -B -q test }
    }
}

# ── Node (NestJS) — tsc · ESLint ──
$nest = "$root\backend\nestjs"
if (Test-Path "$nest\package.json") {
    if (-not $SkipInstall -and -not (Test-Path "$nest\node_modules")) {
        Invoke-Step 'NestJS 의존성 설치' $nest { npm ci --no-audit --no-fund }
    }
    Invoke-Step 'NestJS 타입 검사(tsc strict)' $nest { npm run typecheck }
    Invoke-Step 'NestJS ESLint'               $nest { npm run lint }
    Invoke-Step 'NestJS 단위 테스트'           $nest { npm run test:unit }
}

# ── Python (FastAPI) — Ruff · mypy · pytest ──
$fa = "$root\backend\fastapi"
if (Test-Path "$fa\pyproject.toml") {
    $venvPy = "$fa\.venv\Scripts\python.exe"
    if (-not $SkipInstall -and -not (Test-Path $venvPy)) {
        Invoke-Step 'FastAPI 가상환경 생성' $fa { python -m venv .venv }
        Invoke-Step 'FastAPI 의존성 설치'   $fa { & "$fa\.venv\Scripts\python.exe" -m pip install -q --upgrade pip; & "$fa\.venv\Scripts\python.exe" -m pip install -q -r requirements-dev.txt }
    }
    if (Test-Path $venvPy) {
        Invoke-Step 'FastAPI Ruff'      $fa { & "$fa\.venv\Scripts\ruff.exe" check . }
        Invoke-Step 'FastAPI mypy'      $fa { & "$fa\.venv\Scripts\mypy.exe" app }
        Invoke-Step 'FastAPI 단위 테스트' $fa { & $venvPy -m pytest -q }
    } else {
        Write-Host '  [INFO] .venv 없음 — Python 2차 검증을 건너뜁니다.' -ForegroundColor Yellow
    }
}

# ── Frontend HTML5 — ESLint ──
$h5 = "$root\frontend\html5"
if (Test-Path "$h5\package.json") {
    if (-not $SkipInstall -and -not (Test-Path "$h5\node_modules")) {
        Invoke-Step 'HTML5 의존성 설치' $h5 { npm install --no-audit --no-fund }
    }
    Invoke-Step 'HTML5 ESLint' $h5 { npm run lint }
}

# ── Frontend Vue — ESLint · build ──
$vue = "$root\frontend\vue"
if (Test-Path "$vue\package.json") {
    if (-not $SkipInstall -and -not (Test-Path "$vue\node_modules")) {
        Invoke-Step 'Vue 의존성 설치' $vue { npm ci --no-audit --no-fund }
    }
    Invoke-Step 'Vue ESLint'  $vue { npm run lint }
    Invoke-Step 'Vue 빌드 검증' $vue { npm run build }
}

# ── 리포트 ──
$fail = ($results | Where-Object { $_.Status -ne 'Pass' }).Count
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$payload = [ordered]@{
    kind = 'static-all'
    timestamp = (Get-Date).ToString('s')
    total = $results.Count
    pass = $results.Count - $fail
    fail = $fail
    results = $results
}
$out = "$reportDir\static_all_$stamp.json"
$payload | ConvertTo-Json -Depth 5 | Out-File $out -Encoding utf8

Write-Host ""
Write-Host ("합계 {0}건 · 통과 {1} · 실패 {2}" -f $results.Count, ($results.Count - $fail), $fail) `
    -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("리포트: " + $out) -ForegroundColor Gray

if ($fail -gt 0 -and -not $ContinueOnError) { exit 1 }
