<#  prd 전체 파이프라인 — 전제조건 → 인프라 구성 → 빌드 → 승격 배포 → 테스트 → 운영 준비 검증
    ⚠️ 운영 등급 리소스를 만듭니다. 실행 전 비용을 확인하세요.
    실행: pwsh -File .\run_all.ps1
#>
[CmdletBinding()]
param([string]$AppPath, [switch]$SkipTests, [switch]$WithCleanup, [switch]$Force)
. "$PSScriptRoot\..\common\lib.ps1"

$steps = @(
    @{ n='전제조건';        f='10_prereq.ps1' },
    @{ n='인프라 구성';     f='20_config.ps1' },
    @{ n='빌드(ACR)';       f='30_build.ps1' },
    @{ n='승격 배포';       f='40_deploy.ps1' }
)
if (-not $SkipTests) {
    $steps += @{ n='단위 테스트'; f='50_test_unit.ps1' }
    $steps += @{ n='통합 테스트'; f='60_test_integration.ps1' }
    $steps += @{ n='E2E 스모크';  f='70_test_e2e.ps1' }
}
$steps += @{ n='운영 준비 검증'; f='80_verify.ps1' }
if ($WithCleanup) { $steps += @{ n='정리'; f='90_cleanup.ps1' } }

$log = @(); $sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($s in $steps) {
    $t0 = $sw.Elapsed
    Write-Host ""; Write-Host ("###### prd · {0} ({1}) ######" -f $s.n, $s.f) -ForegroundColor Magenta
    $a = @('-File', (Join-Path $PSScriptRoot $s.f))
    if ($AppPath) { $a += @('-AppPath', $AppPath) }
    if ($Force)   { $a += '-Force' }
    & pwsh @a
    $code = $LASTEXITCODE
    $log += [ordered]@{ Name=$s.n; Status=$(if($code -eq 0){'Pass'}else{'Fail'}); Detail=("{0} · {1:mm\:ss}" -f $s.f, ($sw.Elapsed-$t0)) }
    if ($code -ne 0) { Write-Err2 ("중단: {0} 실패 — 운영 배포를 롤백할지 판단하세요." -f $s.n); break }
}
Write-Host ""; Write-Step "prd 파이프라인 요약"
$ok = New-TestReport -Env 'prd' -Kind 'pipeline' -Results $log -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok ("prd 파이프라인 완료 — 총 {0:mm\:ss}" -f $sw.Elapsed)
