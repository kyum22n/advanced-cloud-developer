<#  prd 단위 테스트 — 릴리스 후보 코드 자체 검증(게이트)
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\50_test_unit.ps1 [-Force]
    ⚠️ 운영 환경 스크립트입니다. 파괴적 작업은 반드시 확인을 거칩니다.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.prd.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath
$RG  = $cfg.azure.resourceGroup

Write-Step "단위 테스트 (Unit) — 릴리스 게이트"
$app = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) { Invoke-Checked -What 'npm install' -Script { npm install --no-audit --no-fund } }
    npm run test:unit
    $code = $LASTEXITCODE
} finally { Pop-Location }
$results = @([ordered]@{ Name='단위 테스트 스위트'; Status=$(if($code -eq 0){'Pass'}else{'Fail'}); Detail="exit=$code" })
$ok = New-TestReport -Env 'prd' -Kind 'unit' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { Write-Err2 '단위 테스트 실패 — 운영 배포를 진행하지 마세요.'; exit 1 }
Write-Ok '단위 테스트 통과 — 다음: .\60_test_integration.ps1'
