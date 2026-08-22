<#
  배포 스크립트 공통 라이브러리
  사용: . "$PSScriptRoot\..\common\lib.ps1"
#>
$ErrorActionPreference = 'Stop'
$script:StepNo = 0

function Write-Step {
    param([string]$Message)
    $script:StepNo++
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host ("[{0}] {1}" -f $script:StepNo, $Message) -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
}
function Write-Ok   { param([string]$m) Write-Host ("  [OK]   " + $m) -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host ("  [INFO] " + $m) -ForegroundColor Gray }
function Write-Warn2{ param([string]$m) Write-Host ("  [WARN] " + $m) -ForegroundColor Yellow }
function Write-Err2 { param([string]$m) Write-Host ("  [FAIL] " + $m) -ForegroundColor Red }

function Assert-Command {
    <# 명령 존재 여부 확인. 없으면 설치 안내 후 예외 #>
    param([Parameter(Mandatory)][string]$Name, [string]$Hint = '')
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Err2 ("'{0}' 명령을 찾을 수 없습니다. {1}" -f $Name, $Hint)
        throw ("필수 도구 누락: {0}" -f $Name)
    }
    Write-Ok ("{0} 확인" -f $Name)
    return $true
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Checked {
    <# 외부 명령 실행 후 종료 코드 검사 #>
    param([Parameter(Mandatory)][scriptblock]$Script, [string]$What = '명령')
    Write-Info ("실행: " + $What)
    & $Script
    if ($LASTEXITCODE -ne 0) { throw ("{0} 실패 (exit={1})" -f $What, $LASTEXITCODE) }
}

function Get-DeployConfig {
    <# config/env.*.json 로드 후 해시테이블 반환 #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw ("설정 파일이 없습니다: " + $Path) }
    $cfg = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Ok ("설정 로드: " + (Split-Path $Path -Leaf))
    return $cfg
}

function Get-GitSha {
    param([string]$Fallback = 'local')
    try {
        $sha = (git rev-parse --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $sha) { return $sha.Trim() }
    } catch { }
    return $Fallback
}

function Wait-Condition {
    <# 조건이 참이 될 때까지 폴링 #>
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [int]$TimeoutSec = 300,
        [int]$IntervalSec = 5,
        [string]$What = '조건'
    )
    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        try { if (& $Condition) { Write-Ok ("{0} 충족 ({1}초)" -f $What, $elapsed); return $true } }
        catch { }
        Start-Sleep -Seconds $IntervalSec
        $elapsed += $IntervalSec
        Write-Info ("{0} 대기 중... {1}/{2}초" -f $What, $elapsed, $TimeoutSec)
    }
    throw ("{0} 대기 시간 초과 ({1}초)" -f $What, $TimeoutSec)
}

function Test-HttpOk {
    <# HTTP 200 응답 확인 #>
    param([Parameter(Mandatory)][string]$Url, [int]$TimeoutSec = 10)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Confirm-Destructive {
    <# 파괴적 작업 전 확인. -Force 지정 시 통과 #>
    param([Parameter(Mandatory)][string]$Target, [switch]$Force)
    if ($Force) { Write-Warn2 ("-Force 지정됨 — 확인 없이 진행: " + $Target); return $true }
    Write-Host ""
    Write-Warn2 ("되돌릴 수 없는 작업입니다: " + $Target)
    $a = Read-Host "계속하려면 정확히 'yes' 를 입력하세요"
    if ($a -ne 'yes') { Write-Info '취소했습니다.'; return $false }
    return $true
}

function New-TestReport {
    <# 테스트 결과를 JSON + 콘솔 표로 기록 #>
    param(
        [Parameter(Mandatory)][string]$Env,
        [Parameter(Mandatory)][string]$Kind,      # unit | integration | e2e | verify
        [Parameter(Mandatory)][array]$Results,    # @{Name;Status;Detail}
        [string]$OutDir
    )
    if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'reports' }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $file  = Join-Path $OutDir ("{0}_{1}_{2}.json" -f $Env, $Kind, $stamp)
    $pass  = ($Results | Where-Object { $_.Status -eq 'Pass' }).Count
    $fail  = ($Results | Where-Object { $_.Status -eq 'Fail' }).Count
    $obj = [ordered]@{
        environment = $Env; kind = $Kind; timestamp = (Get-Date).ToString('s')
        total = $Results.Count; pass = $pass; fail = $fail; results = $Results
    }
    $obj | ConvertTo-Json -Depth 6 | Out-File $file -Encoding utf8
    Write-Host ""
    Write-Host ("  {0,-46} {1,-6}" -f '테스트', '결과') -ForegroundColor White
    Write-Host ("  " + ("-" * 54)) -ForegroundColor DarkGray
    foreach ($r in $Results) {
        $c = if ($r.Status -eq 'Pass') { 'Green' } else { 'Red' }
        Write-Host ("  {0,-46} {1,-6}" -f $r.Name, $r.Status) -ForegroundColor $c
    }
    Write-Host ("  " + ("-" * 54)) -ForegroundColor DarkGray
    Write-Host ("  합계 {0} · 통과 {1} · 실패 {2}" -f $Results.Count, $pass, $fail) -ForegroundColor White
    Write-Info ("리포트: " + $file)
    return ($fail -eq 0)
}

function Resolve-AppPath {
    <# 앱 소스 경로 결정: 사용자 지정 > 실습산출물 myapp > 공통 샘플 앱 #>
    param([string]$AppPath, [Parameter(Mandatory)][string]$RepoRoot)
    if ($AppPath -and (Test-Path $AppPath)) { Write-Ok ("앱 경로(지정): " + $AppPath); return (Resolve-Path $AppPath).Path }
    $myapp = Join-Path $RepoRoot '실습산출물\3차시\myapp'
    if (Test-Path (Join-Path $myapp 'Dockerfile')) { Write-Ok ("앱 경로(실습 산출물): " + $myapp); return (Resolve-Path $myapp).Path }
    $sample = Join-Path $RepoRoot '배포\common\app'
    Write-Warn2 '실습 산출물(myapp)이 없어 공통 샘플 앱을 사용합니다.'
    return (Resolve-Path $sample).Path
}
