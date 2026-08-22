<#  GLM 전체 파이프라인 — 10 → 80
    실행: pwsh -File .\run_all.ps1 [-Force]

    ⚠️ 40 배포부터 GPU 과금이 시작됩니다. 종료 후 반드시 90_cleanup.ps1 을 실행하세요.
#>
[CmdletBinding()]
param([switch]$Force, [string]$BaseUrl = 'http://localhost:8000')

. "$PSScriptRoot\lib.ps1"
$steps = @(
    @{ n = '10_prereq'; f = '10_prereq.ps1'; a = @{} },
    @{ n = '20_config'; f = '20_config.ps1'; a = @{ Force = $Force } },
    @{ n = '30_build';  f = '30_build.ps1';  a = @{} },
    @{ n = '40_deploy'; f = '40_deploy.ps1'; a = @{} }
)
$done = @()
foreach ($s in $steps) {
    Write-Step ("파이프라인: " + $s.n)
    & (Join-Path $PSScriptRoot $s.f) @($s.a)
    if ($LASTEXITCODE -ne 0) {
        Write-Err2 ($s.n + " 실패 — 중단합니다.")
        exit 1
    }
    $done += $s.n
}

Write-Step "50~80 은 포트포워딩이 필요합니다"
Write-Info "다른 터미널에서:"
Write-Info ("  kubectl port-forward -n glm-serving svc/glm 8000:8000")
Write-Info "그 뒤 순서대로:"
Write-Info "  pwsh -File .\50_smoke.ps1                       # 기능 G-F"
Write-Info "  pwsh -File .\60_perf.ps1                        # 성능 G-P"
Write-Info "  pwsh -File .\70_accuracy.ps1 -Mode Baseline     # 기준 응답 수집(최초 1회)"
Write-Info "  pwsh -File .\70_accuracy.ps1 -Mode Compare      # 양자화 회귀 G-Q"
Write-Info "  pwsh -File .\80_verify.ps1                      # 비용·보안 G-C·G-S"
Write-Warn2 "종료 시 반드시: pwsh -File .\90_cleanup.ps1"
