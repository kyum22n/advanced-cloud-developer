<#  prd 통합 테스트 — PaaS 의존성(PostgreSQL·Redis·Key Vault) 연결 검증
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\60_test_integration.ps1 [-Force]
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

Write-Step "통합 테스트 (Integration) — PaaS 의존성 연결 확인"
$app  = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$base = $cfg.test.baseUrl
$ns   = $cfg.app.namespace
if (-not $base) { Write-Err2 'baseUrl 이 비어 있습니다. .\40_deploy.ps1 을 먼저 실행하세요.'; exit 1 }

$results = @()
function Add-I { param($n,$ok,$d) $script:results += [ordered]@{ Name=$n; Status=$(if($ok){'Pass'}else{'Fail'}); Detail=$d } }

# 1) Key Vault 비밀이 파드에 주입되었는가 (값은 확인하지 않고 '키 존재'만 본다)
$keys = kubectl get secret myapp-secret -n $ns -o jsonpath='{.data}' 2>$null
foreach ($k in @('DB_HOST','DB_USER','DB_PASSWORD','REDIS_HOST')) {
    Add-I ("Key Vault → Secret 주입: " + $k) ([bool]($keys -match $k)) 'CSI 드라이버 동기화'
}
# 2) /readyz 가 200 이면 앱이 PaaS PostgreSQL 에 실제로 붙은 것
Add-I 'PaaS PostgreSQL 연결 (/readyz)' (Test-HttpOk -Url ($base + '/readyz')) ($base + '/readyz')

# 3) HTTP API 통합 스위트 (운영은 읽기 전용)
Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) { Invoke-Checked -What 'npm install' -Script { npm install --no-audit --no-fund } }
    $env:BASE_URL = $base
    $env:ALLOW_WRITE = "$($cfg.test.allowWrite)".ToLower()
    npm run test:integration
    $code = $LASTEXITCODE
} finally { Pop-Location; Remove-Item Env:BASE_URL, Env:ALLOW_WRITE -ErrorAction SilentlyContinue }
Add-I ("API 통합 스위트 (쓰기=" + $cfg.test.allowWrite + ")") ($code -eq 0) "exit=$code"

$ok = New-TestReport -Env 'prd' -Kind 'integration' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok '통합 테스트 통과 — 다음: .\70_test_e2e.ps1'
