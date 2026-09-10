<#
.SYNOPSIS
    테스트 전체 실행 — 스모크 → 계약 → 통합 → E2E.

.DESCRIPTION
    순서에 의미가 있다. 앞 단계가 실패하면 뒤는 돌릴 이유가 없다.
      스모크가 실패 = 서비스가 안 떠 있다 → 나머지는 전부 실패한다
      계약이 실패   = API 형식이 다르다   → 통합·E2E 는 원인을 알기 어렵게 만든다

    -ContinueOnFailure 를 주면 실패해도 끝까지 돌린다 (전체 상태를 볼 때).

.EXAMPLE
    .\run_tests.ps1 -Env dev
    .\run_tests.ps1 -BaseUrl http://localhost:8081 -ContinueOnFailure
#>
[CmdletBinding()]
param(
    [string]$Env = 'local',
    [string]$BaseUrl = '',
    [switch]$ContinueOnFailure,
    [switch]$SkipE2E
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$suites = @(
    @{ N = '10'; Name = '스모크';   Path = 'integration\10_smoke.ps1' }
    @{ N = '20'; Name = '계약';     Path = 'integration\20_contract.ps1' }
    @{ N = '30'; Name = '통합';     Path = 'integration\30_saga.ps1' }
    @{ N = '50'; Name = 'E2E';      Path = 'e2e\50_delivery_journey.ps1' }
)

if ($SkipE2E) {
    $suites = $suites | Where-Object { $_.N -ne '50' }
}

Write-Host ''
Write-Host ('=' * 66) -ForegroundColor Cyan
Write-Host ' 드론 배달 — 테스트 실행' -ForegroundColor Cyan
Write-Host ('=' * 66) -ForegroundColor Cyan
Write-Host " 환경: $Env"
if ($BaseUrl) { Write-Host " 주소: $BaseUrl" }

$totalFail = 0
$summary = @()

foreach ($s in $suites) {
    $script = Join-Path $root $s.Path
    if (-not (Test-Path $script)) {
        Write-Host "  ! $($s.Name) 스크립트를 찾을 수 없습니다: $script" -ForegroundColor Yellow
        continue
    }

    $params = @{ Env = $Env }
    if ($BaseUrl) { $params['BaseUrl'] = $BaseUrl }

    & $script @params
    $fail = $LASTEXITCODE
    $totalFail += $fail
    $summary += [pscustomobject]@{ Suite = $s.Name; Failures = $fail }

    if ($fail -ne 0 -and -not $ContinueOnFailure) {
        Write-Host ''
        Write-Host " ✗ $($s.Name) 에서 실패했습니다. 여기서 멈춥니다." -ForegroundColor Red
        Write-Host '   전체를 계속 돌리려면 -ContinueOnFailure 를 주세요.'
        break
    }
}

Write-Host ''
Write-Host ('=' * 66)
Write-Host ' 요약'
foreach ($s in $summary) {
    $color = if ($s.Failures -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("   {0,-10} 실패 {1}" -f $s.Suite, $s.Failures) -ForegroundColor $color
}
Write-Host ('=' * 66)

if ($totalFail -eq 0) {
    Write-Host ' 전체 통과' -ForegroundColor Green
} else {
    Write-Host " 전체 실패 $totalFail 건" -ForegroundColor Red
}

exit $totalFail
