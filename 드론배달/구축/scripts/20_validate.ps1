<#
.SYNOPSIS
    정적 검증 — 아무것도 만들지 않는다.

.DESCRIPTION
    실행 «전»에 잡을 수 있는 문제를 전부 잡는다. 계층이 넷이다.
      ① terraform fmt      형식
      ② 자체 정적 검증기   모듈 참조 · 변수 · 보안 규칙 (파이썬만 있으면 동작)
      ③ terraform validate 문법 · 타입 (프로바이더 필요)
      ④ tflint · checkov   Azure 규칙 · 보안 정책 (있으면 실행)

    ②는 도구가 없어도 항상 돌아가는 «최소 방어선»이다.

.EXAMPLE
    .\20_validate.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'stg', 'prd')][string]$Env
)

. "$PSScriptRoot\lib.ps1"

Write-Head "정적 검증 — $Env"

$tfRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'terraform'
$envDir = Get-EnvDir $Env

# ── ① 형식
Write-Step 'terraform fmt'
Push-Location $tfRoot
try {
    & terraform fmt -recursive -check | Out-Null
    Add-Check 'F-fmt' '형식이 정렬되어 있음' ($LASTEXITCODE -eq 0) `
        'terraform fmt -recursive 로 정렬하세요'
} finally {
    Pop-Location
}

# ── ② 자체 정적 검증기 (도구 없이도 동작)
Write-Step '자체 정적 검증'
$py = if (Test-Command 'python') { 'python' } elseif (Test-Command 'py') { 'py' } else { $null }
if ($null -eq $py) {
    Write-Warn2 'python 이 없어 자체 검증을 건너뜁니다'
} else {
    $env:PYTHONUTF8 = '1'
    & $py (Join-Path $PSScriptRoot 'validate_terraform.py') $tfRoot
    Add-Check 'F-static' '모듈 참조 · 변수 · 보안 규칙' ($LASTEXITCODE -eq 0) `
        '위 출력의 실패 항목을 확인하세요'
}

# ── ③ terraform validate
Write-Step 'terraform validate'
Push-Location $envDir
try {
    # -backend=false — 상태 저장소에 접근하지 않고 문법만 본다.
    & terraform init -backend=false -input=false | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Add-Check 'F-init' 'terraform init' $false '프로바이더를 내려받지 못했습니다'
    } else {
        & terraform validate
        Add-Check 'F-validate' 'terraform validate' ($LASTEXITCODE -eq 0)
    }
} finally {
    Pop-Location
}

# ── ④ 선택 도구
Write-Step '추가 도구 (설치되어 있으면 실행)'

if (Test-Command 'tflint') {
    Push-Location $tfRoot
    try {
        & tflint --recursive
        Add-Check 'F-tflint' 'tflint' ($LASTEXITCODE -eq 0)
    } finally { Pop-Location }
} else {
    Write-Warn2 'tflint 없음 — 건너뜁니다 (권장: Azure 규칙 검사)'
}

if (Test-Command 'checkov') {
    & checkov -d $tfRoot --quiet --compact --framework terraform
    # checkov 는 발견 사항이 있으면 0 이 아닌 코드를 낸다.
    Add-Check 'F-checkov' 'checkov 보안 정책' ($LASTEXITCODE -eq 0)
} else {
    Write-Warn2 'checkov 없음 — 건너뜁니다 (권장: 보안 정책 검사)'
}

$failCount = Save-Results -Env "${Env}_validate" -OutDir (Join-Path $PSScriptRoot '..\검증결과')

Write-Host ''
if ($failCount -eq 0) {
    Write-Host '다음: .\30_plan.ps1 -Env ' -NoNewline; Write-Host $Env -ForegroundColor Cyan
}
exit $failCount
