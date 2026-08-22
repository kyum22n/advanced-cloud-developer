<#  prd E2E 스모크 — 읽기 전용으로 실제 사용자 경로 확인
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\70_test_e2e.ps1 [-Force]
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

Write-Step "E2E 스모크 테스트 (운영 — 읽기 전용 원칙)"
$app  = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$base = $cfg.test.baseUrl
if (-not $base) { Write-Err2 'baseUrl 이 비어 있습니다.'; exit 1 }
Write-Info ("쓰기 테스트 허용: " + $cfg.test.allowWrite + " (운영은 false 가 기본 — 쓰기 검증은 stg 에서 끝냅니다)")

Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) { Invoke-Checked -What 'npm install' -Script { npm install --no-audit --no-fund } }
    npx playwright install chromium 2>&1 | Out-Null
    $env:BASE_URL = $base; $env:APP_ENV = 'prd'; $env:ALLOW_WRITE = "$($cfg.test.allowWrite)".ToLower()
    npx playwright test --project=chromium
    $code = $LASTEXITCODE
} finally { Pop-Location; Remove-Item Env:BASE_URL, Env:APP_ENV, Env:ALLOW_WRITE -ErrorAction SilentlyContinue }

$shot = Join-Path $app 'test\e2e\캡처'
$n = 0; if (Test-Path $shot) { $n = (Get-ChildItem $shot -Filter 'prd_*.png' -ErrorAction SilentlyContinue).Count }
$results = @(
  [ordered]@{ Name="E2E 스모크 ($base)"; Status=$(if($code -eq 0){'Pass'}else{'Fail'}); Detail="exit=$code" },
  [ordered]@{ Name='prd 캡처 생성'; Status=$(if($n -gt 0){'Pass'}else{'Fail'}); Detail="$n 개" }
)
$ok = New-TestReport -Env 'prd' -Kind 'e2e' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok "E2E 스모크 통과 — 다음: .\80_verify.ps1"
