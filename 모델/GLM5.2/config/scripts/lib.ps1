<#  GLM 배포 공통 함수 — 배포/common/lib.ps1 과 같은 규칙을 따른다. #>
$script:StepNo = 0

function Write-Step {
    param([string]$m)
    $script:StepNo++
    Write-Host ""
    Write-Host ("== [{0}] {1} " -f $script:StepNo, $m).PadRight(78, '=') -ForegroundColor Cyan
}
function Write-Ok   { param([string]$m) Write-Host ("  [OK]   " + $m) -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host ("  [INFO] " + $m) -ForegroundColor Gray }
function Write-Warn2{ param([string]$m) Write-Host ("  [WARN] " + $m) -ForegroundColor Yellow }
function Write-Err2 { param([string]$m) Write-Host ("  [FAIL] " + $m) -ForegroundColor Red }

function Get-GlmConfig {
    param([string]$Path = "$PSScriptRoot\..\env.glm.json")
    if (-not (Test-Path $Path)) { throw "설정 파일이 없습니다: $Path" }
    Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-GlmModel {
    param([string]$Path = "$PSScriptRoot\..\model.json")
    Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Invoke-Checked {
    param([string]$What, [scriptblock]$Script)
    Write-Info ("실행: " + $What)
    & $Script
    if ($LASTEXITCODE -ne 0) { throw ($What + " 실패 (exit=" + $LASTEXITCODE + ")") }
    Write-Ok $What
}

function Confirm-Destructive {
    param([string]$Target, [switch]$Force)
    if ($Force) { return $true }
    Write-Warn2 ("파괴적 작업입니다: " + $Target)
    $answer = Read-Host "계속하려면 'yes' 를 입력하세요"
    if ($answer -ne 'yes') { Write-Info '취소했습니다.'; return $false }
    return $true
}

function New-GlmReport {
    param([string]$Kind, [array]$Results, [string]$OutDir = "$PSScriptRoot\reports")
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $fail = ($Results | Where-Object { $_.Status -ne 'Pass' }).Count
    $payload = [ordered]@{
        kind = $Kind
        timestamp = (Get-Date).ToString('s')
        total = $Results.Count
        pass = $Results.Count - $fail
        fail = $fail
        results = $Results
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $out = Join-Path $OutDir ("glm_" + $Kind + "_" + $stamp + ".json")
    $payload | ConvertTo-Json -Depth 6 | Out-File $out -Encoding utf8
    Write-Host ""
    foreach ($r in $Results) {
        $mark = if ($r.Status -eq 'Pass') { '  [PASS]' } else { '  [FAIL]' }
        $color = if ($r.Status -eq 'Pass') { 'Green' } else { 'Red' }
        Write-Host ("{0} {1} — {2}" -f $mark, $r.Name, $r.Detail) -ForegroundColor $color
    }
    Write-Host ("  합계 {0} · 통과 {1} · 실패 {2}" -f $Results.Count, ($Results.Count - $fail), $fail) `
        -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
    Write-Info ("리포트: " + $out)
    return ($fail -eq 0)
}
