<#  stg 단위 테스트 — 배포와 무관하게 코드 자체를 검증
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\50_test_unit.ps1 [-Force]
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

Write-Step "단위 테스트 (Unit)"
$app = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) { Invoke-Checked -What 'npm install' -Script { npm install --no-audit --no-fund } }
    npm run test:unit
    $code = $LASTEXITCODE
} finally { Pop-Location }

$results = @([ordered]@{ Name='단위 테스트 스위트 (test/unit)'; Status=$(if($code -eq 0){'Pass'}else{'Fail'}); Detail="exit=$code" })
$ok = New-TestReport -Env 'stg' -Kind 'unit' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok '단위 테스트 통과 — 다음: .\60_test_integration.ps1'
