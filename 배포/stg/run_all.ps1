<#  stg 전체 파이프라인 — 전제조건 → 구성(AKS·ACR·Argo CD) → 빌드(ACR) → GitOps 배포 → 테스트 → 검증
    실행: pwsh -File .\run_all.ps1
#>
[CmdletBinding()]
param([string]$AppPath, [switch]$SkipTests, [switch]$WithCleanup, [switch]$Force)
. "$PSScriptRoot\..\common\lib.ps1"

$steps = @(
    @{ n='전제조건';       f='10_prereq.ps1' },
    @{ n='구성(AKS·ArgoCD)';f='20_config.ps1' },
    @{ n='빌드(ACR)';      f='30_build.ps1' },
    @{ n='GitOps 배포';    f='40_deploy.ps1' }
)
if (-not $SkipTests) {
    $steps += @{ n='단위 테스트'; f='50_test_unit.ps1' }
    $steps += @{ n='통합 테스트'; f='60_test_integration.ps1' }
    $steps += @{ n='E2E 테스트';  f='70_test_e2e.ps1' }
}
$steps += @{ n='배포 검증'; f='80_verify.ps1' }
if ($WithCleanup) { $steps += @{ n='정리'; f='90_cleanup.ps1' } }

$log = @(); $sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($s in $steps) {
    $t0 = $sw.Elapsed
    Write-Host ""; Write-Host ("###### stg · {0} ({1}) ######" -f $s.n, $s.f) -ForegroundColor Magenta
    $a = @('-File', (Join-Path $PSScriptRoot $s.f))
    if ($AppPath) { $a += @('-AppPath', $AppPath) }
    if ($Force)   { $a += '-Force' }
    & pwsh @a
    $code = $LASTEXITCODE
    $log += [ordered]@{ Name=$s.n; Status=$(if($code -eq 0){'Pass'}else{'Fail'}); Detail=("{0} · {1:mm\:ss}" -f $s.f, ($sw.Elapsed-$t0)) }
    if ($code -ne 0) { Write-Err2 ("중단: {0} 실패" -f $s.n); break }
}
Write-Host ""; Write-Step "stg 파이프라인 요약"
$ok = New-TestReport -Env 'stg' -Kind 'pipeline' -Results $log -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok ("stg 파이프라인 완료 — 총 {0:mm\:ss}" -f $sw.Elapsed)
