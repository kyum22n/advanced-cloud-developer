<#
.SYNOPSIS
    인프라 적용 — ⚠️ 실제로 Azure 리소스를 만든다.

.DESCRIPTION
    30_plan 이 만든 계획 파일을 그대로 적용한다.
    계획 없이 apply 하지 않는다 — 「검토한 것」과 「적용한 것」이 달라지기 때문이다.

    이 스크립트는 자동으로 실행되지 않는다. 사람이 확인 프롬프트에 응답해야 한다.

.EXAMPLE
    .\40_apply.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'stg', 'prd')][string]$Env
)

. "$PSScriptRoot\lib.ps1"

Write-Head "인프라 적용 — $Env"

$envDir   = Get-EnvDir $Env
$planFile = Join-Path $envDir 'tfplan'

if (-not (Test-Path $planFile)) {
    Write-Fail '계획 파일이 없습니다. 먼저 30_plan.ps1 을 실행하세요.'
    exit 1
}

# 계획이 오래됐으면 인프라가 그사이 바뀌었을 수 있다.
$age = (Get-Date) - (Get-Item $planFile).LastWriteTime
if ($age.TotalMinutes -gt 30) {
    Write-Warn2 ("계획이 {0:N0}분 전에 만들어졌습니다. 다시 계획하는 것을 권합니다." -f $age.TotalMinutes)
}

# prd 는 두 번 확인한다.
if ($Env -eq 'prd') {
    Write-Host ''
    Write-Host '🛑 운영 환경입니다.' -ForegroundColor Red
    Write-Host ''
    Write-Host '   확인했습니까?'
    Write-Host '     ① stg 검증 결과의 fail = 0'
    Write-Host '     ② 계획에 데이터 저장소 삭제가 없음'
    Write-Host '     ③ 운영 담당자의 승인'
    Write-Host ''

    if (-not (Confirm-Destructive -Action '운영 인프라 변경 적용' -Target "$Env ($envDir)")) {
        exit 1
    }
}

if (-not (Confirm-Destructive -Action 'terraform apply' -Target "$Env 환경의 Azure 리소스")) {
    exit 1
}

Write-Step 'terraform apply'
Invoke-Terraform -EnvDir $envDir -Arguments @('apply', '-input=false', 'tfplan')

Write-Step '출력 저장'
$outDir = Join-Path $PSScriptRoot '..\출력'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Push-Location $envDir
try {
    # ⚠️ 이 파일에는 엔드포인트 주소가 들어간다. 비밀은 sensitive 로 가려지지만,
    #    그래도 이 파일을 Git 에 커밋하지 않는다.
    & terraform output -json | Out-File -FilePath (Join-Path $outDir "env.$Env.json") -Encoding utf8
} finally {
    Pop-Location
}
Write-Ok "출력을 저장했습니다: 출력\env.$Env.json"

# 계획 파일은 한 번 쓰면 버린다 — 재사용하면 «이미 적용된 계획»을 다시 적용하게 된다.
Remove-Item $planFile -ErrorAction SilentlyContinue
Remove-Item (Join-Path $envDir 'tfplan.json') -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '다음: .\80_verify.ps1 -Env ' -NoNewline; Write-Host $Env -ForegroundColor Cyan
exit 0
