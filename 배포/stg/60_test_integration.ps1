<#  stg 통합 테스트 — AKS 에 배포된 API + DB 연동 검증
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\60_test_integration.ps1 [-Force]
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.stg.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath
$RG  = $cfg.azure.resourceGroup

Write-Step "통합 테스트 (Integration)"
$app  = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$base = $cfg.test.baseUrl
if (-not $base) { Write-Err2 'baseUrl 이 비어 있습니다. .\40_deploy.ps1 을 먼저 실행하세요.'; exit 1 }
Write-Info ("대상: " + $base)

if (-not (Test-HttpOk -Url ($base + '/healthz'))) { Write-Err2 '앱이 응답하지 않습니다.'; exit 1 }

Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) { Invoke-Checked -What 'npm install' -Script { npm install --no-audit --no-fund } }
    $env:BASE_URL = $base
    $env:ALLOW_WRITE = "$($cfg.test.allowWrite)".ToLower()
    npm run test:integration
    $code = $LASTEXITCODE
} finally { Pop-Location; Remove-Item Env:BASE_URL, Env:ALLOW_WRITE -ErrorAction SilentlyContinue }

$results = @([ordered]@{ Name="통합 테스트 스위트 ($base)"; Status=$(if($code -eq 0){'Pass'}else{'Fail'}); Detail="exit=$code" })
$ok = New-TestReport -Env 'stg' -Kind 'integration' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok '통합 테스트 통과 — 다음: .\70_test_e2e.ps1'
