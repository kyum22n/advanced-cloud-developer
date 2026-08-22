<#  dev E2E 테스트 — 실제 브라우저로 화면 검증 + 캡처
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\70_test_e2e.ps1 [-Force]
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.dev.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath

Write-Step "E2E 테스트 (End-to-End · Playwright)"

$app  = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$base = $cfg.test.baseUrl

if (-not (Test-HttpOk -Url ($base + "/healthz"))) {
    Write-Err2 "앱이 응답하지 않습니다. .\40_deploy.ps1 을 먼저 실행하세요."
    exit 1
}

Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) { Invoke-Checked -What 'npm install' -Script { npm install --no-audit --no-fund } }
    Write-Info 'Playwright 브라우저 준비(최초 1회 다운로드)'
    npx playwright install chromium 2>&1 | Out-Null

    $env:BASE_URL    = $base
    $env:APP_ENV     = 'dev'
    $env:ALLOW_WRITE = "$($cfg.test.allowWrite)".ToLower()
    npx playwright test --project=chromium 2>&1 | Tee-Object -Variable e2eOut
    $code = $LASTEXITCODE
} finally { Pop-Location; Remove-Item Env:BASE_URL, Env:APP_ENV, Env:ALLOW_WRITE -ErrorAction SilentlyContinue }

$shot = Join-Path $app 'test\e2e\캡처'
$n = 0; if (Test-Path $shot) { $n = (Get-ChildItem $shot -Filter '*.png' -ErrorAction SilentlyContinue).Count }

$results = @(
    [ordered]@{ Name = "E2E 스위트 (Playwright → $base)"; Status = $(if ($code -eq 0) { 'Pass' } else { 'Fail' }); Detail = "exit=$code" },
    [ordered]@{ Name = '캡처 파일 생성'; Status = $(if ($n -gt 0) { 'Pass' } else { 'Fail' }); Detail = "$n 개 ($shot)" }
)
$ok = New-TestReport -Env 'dev' -Kind 'e2e' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok "E2E 통과 · 캡처 $n 개 — 다음: .\80_verify.ps1"
