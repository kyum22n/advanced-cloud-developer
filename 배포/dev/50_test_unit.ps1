<#  dev 단위 테스트 — 외부 의존 없이 순수 로직 검증
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\50_test_unit.ps1 [-Force]
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

Write-Step "단위 테스트 (Unit)"

$app = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) {
        Write-Info '의존성 설치 중(npm install)...'
        Invoke-Checked -What 'npm install' -Script { npm install --no-audit --no-fund }
    }
    Write-Info '단위 테스트는 DB·네트워크 없이 실행됩니다.'
    npm run test:unit
    $code = $LASTEXITCODE
} finally { Pop-Location }

$results = @([ordered]@{
    Name = '단위 테스트 스위트 (test/unit)'
    Status = $(if ($code -eq 0) { 'Pass' } else { 'Fail' })
    Detail = "npm run test:unit (exit=$code)"
})
$ok = New-TestReport -Env 'dev' -Kind 'unit' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { exit 1 }
Write-Ok '단위 테스트 통과 — 다음: .\60_test_integration.ps1'
