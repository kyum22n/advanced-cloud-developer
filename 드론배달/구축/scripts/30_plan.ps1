<#
.SYNOPSIS
    실행 계획 생성 — 아무것도 만들지 않는다.

.DESCRIPTION
    terraform plan 을 실행하고 «사람이 반드시 확인해야 할 것»을 요약해서 보여 준다.
    계획 파일(tfplan)을 남겨 40_apply 가 «검토한 그 계획»을 그대로 적용하게 한다.

    plan 과 apply 사이에 시간이 벌어지면 그사이 인프라가 바뀔 수 있다.
    계획 파일을 쓰면 «검토한 것과 다른 것이 적용되는» 일이 없다.

.EXAMPLE
    .\30_plan.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'stg', 'prd')][string]$Env
)

. "$PSScriptRoot\lib.ps1"

Write-Head "실행 계획 — $Env"

$envDir   = Get-EnvDir $Env
$planFile = Join-Path $envDir 'tfplan'
$jsonFile = Join-Path $envDir 'tfplan.json'

Write-Step 'terraform init'
Invoke-Terraform -EnvDir $envDir -Arguments @('init', '-input=false')

Write-Step 'terraform plan'
Invoke-Terraform -EnvDir $envDir -Arguments @(
    'plan', '-input=false', '-out=tfplan',
    "-var-file=terraform.tfvars"
)

Write-Step '계획 분석'
Invoke-Terraform -EnvDir $envDir -Arguments @('show', '-json', 'tfplan') `
    2>$null | Out-Null

Push-Location $envDir
try {
    & terraform show -json tfplan | Out-File -FilePath 'tfplan.json' -Encoding utf8
} finally {
    Pop-Location
}

if (-not (Test-Path $jsonFile)) {
    Write-Warn2 '계획 JSON 을 만들지 못했습니다 — 수동으로 terraform show 를 확인하세요'
    exit 0
}

$plan = Get-Content $jsonFile -Raw | ConvertFrom-Json
$changes = @($plan.resource_changes)

$create  = @($changes | Where-Object { $_.change.actions -contains 'create' -and $_.change.actions -notcontains 'delete' })
$update  = @($changes | Where-Object { $_.change.actions -contains 'update' })
$destroy = @($changes | Where-Object { $_.change.actions -contains 'delete' })
$replace = @($changes | Where-Object { $_.change.actions.Count -gt 1 -and $_.change.actions -contains 'delete' -and $_.change.actions -contains 'create' })

Write-Host ''
Write-Host " 생성 $($create.Count) · 변경 $($update.Count) · 삭제 $($destroy.Count) · 재생성 $($replace.Count)"

# ⚠️ 사람이 반드시 눈으로 봐야 하는 것 — 데이터가 사라지는 변경
$DATA_RESOURCES = @(
    'azurerm_cosmosdb_account', 'azurerm_cosmosdb_sql_database',
    'azurerm_cosmosdb_sql_container', 'azurerm_cosmosdb_mongo_database',
    'azurerm_redis_cache', 'azurerm_storage_account', 'azurerm_storage_container',
    'azurerm_key_vault', 'azurerm_servicebus_namespace', 'azurerm_eventhub_namespace'
)

$dangerous = @($destroy | Where-Object { $DATA_RESOURCES -contains $_.type })

if ($dangerous.Count -gt 0) {
    Write-Host ''
    Write-Host '🛑 데이터 저장소가 삭제·재생성 대상입니다:' -ForegroundColor Red
    foreach ($d in $dangerous) {
        Write-Host "     $($d.type).$($d.name)  →  $($d.change.actions -join ',')" -ForegroundColor Red
    }
    Write-Host ''
    Write-Host '   이 계획을 적용하면 데이터가 사라집니다.' -ForegroundColor Red
    Write-Host '   의도한 것이 아니라면 «절대» 적용하지 마세요.' -ForegroundColor Red
}

if ($replace.Count -gt 0) {
    Write-Host ''
    Write-Host '⚠️  재생성(삭제 후 생성) 대상:' -ForegroundColor Yellow
    foreach ($r in $replace) {
        Write-Host "     $($r.type).$($r.name)" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host ('-' * 66)
Write-Host " 계획 파일: $planFile"
Write-Host ''
Write-Host ' ▶ 이 계획을 «직접 읽어» 확인한 뒤에만 적용하세요.'
Write-Host '   확인 항목'
Write-Host '     · 데이터 저장소가 삭제 목록에 없는가'
Write-Host '     · 예상하지 않은 리소스가 있는가 (포털 수동 변경 흔적)'
Write-Host '     · 비밀이 평문으로 보이는가'
Write-Host '     · 태그가 빠진 리소스가 있는가'
Write-Host ''
Write-Host ' 다음: .\40_apply.ps1 -Env ' -NoNewline; Write-Host $Env -ForegroundColor Cyan

exit 0
