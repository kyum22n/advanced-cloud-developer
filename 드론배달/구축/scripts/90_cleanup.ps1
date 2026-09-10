<#
.SYNOPSIS
    리소스 삭제 — ⚠️ 되돌릴 수 없다.

.DESCRIPTION
    실습 후 비용이 계속 나가지 않도록 정리한다.
    반드시 사람이 'yes' 를 입력해야 진행하며, prd 는 한 번 더 확인한다.

    ⚠️ 데이터가 사라진다. Cosmos DB · Storage · Redis 의 내용이 모두 없어진다.

.EXAMPLE
    .\90_cleanup.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'stg', 'prd')][string]$Env
)

. "$PSScriptRoot\lib.ps1"

Write-Head "리소스 정리 — $Env"

$envDir = Get-EnvDir $Env

Write-Host ''
Write-Host '이 작업은 다음을 «영구히» 삭제합니다:' -ForegroundColor Yellow
Write-Host '  · Cosmos DB 의 모든 문서 (드론 · 배달 이력 · 패키지)'
Write-Host '  · Redis 의 모든 키 (진행 중인 배달 상태)'
Write-Host '  · Storage 의 모든 파일 (장기 이력)'
Write-Host '  · Service Bus · Event Hubs 의 미처리 메시지'
Write-Host '  · Key Vault (소프트 삭제 보존 기간 후 영구 삭제)'
Write-Host ''

if ($Env -eq 'prd') {
    Write-Host '🛑 운영 환경을 삭제하려 합니다.' -ForegroundColor Red
    Write-Host '   이것이 정말 의도한 것입니까?' -ForegroundColor Red
    Write-Host ''
    $envName = Read-Host "확인을 위해 환경 이름을 정확히 입력하세요 (prd)"
    if ($envName -ne 'prd') {
        Write-Host '취소했습니다.' -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Confirm-Destructive -Action 'terraform destroy' -Target "$Env 환경의 모든 리소스")) {
    exit 1
}

Write-Step 'terraform destroy 계획'
Invoke-Terraform -EnvDir $envDir -Arguments @(
    'plan', '-destroy', '-input=false', '-out=tfdestroy',
    '-var-file=terraform.tfvars'
)

Write-Host ''
Write-Host '▶ 위 계획을 확인하세요. 삭제 대상이 맞습니까?'
if (-not (Confirm-Destructive -Action '위 계획대로 삭제 실행' -Target "$Env")) {
    Remove-Item (Join-Path $envDir 'tfdestroy') -ErrorAction SilentlyContinue
    exit 1
}

Write-Step 'terraform destroy'
Invoke-Terraform -EnvDir $envDir -Arguments @('apply', '-input=false', 'tfdestroy')

Remove-Item (Join-Path $envDir 'tfdestroy') -ErrorAction SilentlyContinue

Write-Host ''
Write-Ok '삭제를 완료했습니다.'
Write-Host ''
Write-Warn2 'Key Vault 는 소프트 삭제 상태로 남습니다.'
Write-Host '   완전히 지우려면: az keyvault purge --name <이름>'
Write-Host '   (purge_protection 이 켜진 prd 는 보존 기간이 지나야 합니다)'
exit 0
