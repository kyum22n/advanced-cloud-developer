<#
.SYNOPSIS
    배포 후 검증 — 읽기만 한다. 아무것도 바꾸지 않는다.

.DESCRIPTION
    «만들어졌다»와 «제대로 만들어졌다»는 다르다.
    설계서(설계/09_보안_아이덴티티_설계서.md §9)의 검증 케이스를 실제 리소스에 대고 확인한다.

    결과는 JSON 파일로 남는다. prd 승격 조건이 「stg 검증 fail = 0」이므로,
    사람의 기억이 아니라 이 파일이 근거가 된다.

.EXAMPLE
    .\80_verify.ps1 -Env stg
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'stg', 'prd')][string]$Env
)

. "$PSScriptRoot\lib.ps1"

Write-Head "배포 검증 — $Env"

$outFile = Join-Path $PSScriptRoot "..\출력\env.$Env.json"
if (-not (Test-Path $outFile)) {
    Write-Fail "출력 파일이 없습니다: $outFile — 40_apply 를 먼저 실행하세요."
    exit 1
}

$out = Get-Content $outFile -Raw | ConvertFrom-Json
$rg  = $out.resource_group.value

function Get-Json {
    param([string[]]$AzArgs)
    try {
        $raw = & az @AzArgs -o json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

# ═══════════════════════════════════ 1. 리소스 존재
Write-Step '리소스 존재 확인'

$resources = Get-Json @('resource', 'list', '--resource-group', $rg)
Add-Check 'R-01' "리소스 그룹 $rg" ($null -ne $resources) '리소스 그룹을 찾을 수 없습니다'

if ($null -ne $resources) {
    $expected = @(
        @{ Type = 'Microsoft.AppPlatform/Spring';                  Name = 'Spring Apps' }
        @{ Type = 'Microsoft.ServiceBus/namespaces';               Name = 'Service Bus' }
        @{ Type = 'Microsoft.EventHub/namespaces';                 Name = 'Event Hubs' }
        @{ Type = 'Microsoft.DocumentDB/databaseAccounts';         Name = 'Cosmos DB' }
        @{ Type = 'Microsoft.Cache/Redis';                         Name = 'Redis' }
        @{ Type = 'Microsoft.Storage/storageAccounts';             Name = 'Storage' }
        @{ Type = 'Microsoft.KeyVault/vaults';                     Name = 'Key Vault' }
        @{ Type = 'Microsoft.ContainerRegistry/registries';        Name = 'Container Registry' }
        @{ Type = 'Microsoft.OperationalInsights/workspaces';      Name = 'Log Analytics' }
        @{ Type = 'Microsoft.ManagedIdentity/userAssignedIdentities'; Name = '관리 ID' }
    )
    foreach ($e in $expected) {
        $found = @($resources | Where-Object { $_.type -eq $e.Type })
        Add-Check "R-$($e.Name)" "$($e.Name) ($($found.Count)개)" ($found.Count -gt 0)
    }
}

# ═══════════════════════════════════ 2. 아이덴티티 (SEC-V-02 ~ 05)
Write-Step '아이덴티티 — 앱마다 고유 ID · 최소 권한'

$identities = Get-Json @('identity', 'list', '--resource-group', $rg)
$idCount = if ($null -eq $identities) { 0 } else { @($identities).Count }
Add-Check 'SEC-V-02' "앱별 사용자 할당 관리 ID 6개 (현재 $idCount)" ($idCount -ge 6) `
    '앱마다 고유 ID 가 있어야 최소 권한과 감사가 가능합니다'

if ($null -ne $identities) {
    # SEC-V-05 — ID 를 공유하지 않는가
    $uniqueIds = @($identities | Select-Object -ExpandProperty principalId -Unique)
    Add-Check 'SEC-V-05' 'ID 공유 없음' ($uniqueIds.Count -eq $idCount)

    # SEC-V-03 / 04 — 구독 범위 · 과도한 역할
    $subId = (Get-Json @('account', 'show')).id
    $violationsScope = 0
    $violationsRole  = 0

    foreach ($identity in $identities) {
        $assignments = Get-Json @(
            'role', 'assignment', 'list',
            '--assignee', $identity.principalId, '--all'
        )
        foreach ($a in @($assignments)) {
            if ($a.scope -eq "/subscriptions/$subId") { $violationsScope++ }
            if ($a.roleDefinitionName -in @('Contributor', 'Owner', 'User Access Administrator')) {
                $violationsRole++
            }
        }
    }
    Add-Check 'SEC-V-03' '구독 범위 역할 부여 없음' ($violationsScope -eq 0) `
        "$violationsScope 건 발견 — A-01 위반"
    Add-Check 'SEC-V-04' 'Contributor/Owner 역할 없음' ($violationsRole -eq 0) `
        "$violationsRole 건 발견 — A-02 위반"
}

# ═══════════════════════════════════ 3. 비밀 없는 접근 (SEC-V-06 ~ 08)
Write-Step '비밀 없는 접근'

$storageName = $out.storage_account.value
$storage = Get-Json @('storage', 'account', 'show', '--name', $storageName, '--resource-group', $rg)
if ($null -ne $storage) {
    Add-Check 'SEC-V-06' 'Storage 공유 키 접근 비활성' ($storage.allowSharedKeyAccess -eq $false) `
        'allowSharedKeyAccess=true — A-07 위반'
}

$cosmosName = ($out.cosmos_endpoint.value -replace 'https://', '' -split '\.')[0]
$cosmos = Get-Json @('cosmosdb', 'show', '--name', $cosmosName, '--resource-group', $rg)
if ($null -ne $cosmos) {
    Add-Check 'SEC-V-08' 'Cosmos DB 로컬 인증(계정 키) 비활성' `
        ($cosmos.disableLocalAuth -eq $true) 'disableLocalAuth=false — A-08 위반'
}

$sbName = $out.service_bus_namespace.value
$sb = Get-Json @('servicebus', 'namespace', 'show', '--name', $sbName, '--resource-group', $rg)
if ($null -ne $sb) {
    Add-Check 'SEC-V-08b' 'Service Bus 로컬 인증(SAS) 비활성' `
        ($sb.disableLocalAuth -eq $true) 'SAS 키 인증이 열려 있습니다'
}

# ═══════════════════════════════════ 4. 네트워크 (SEC-V-09 ~ 11)
Write-Step '네트워크 격리'

if ($Env -ne 'dev') {
    $paas = @(
        @{ Id = 'SEC-V-09a'; Name = 'Service Bus';  Value = $sb.publicNetworkAccess }
        @{ Id = 'SEC-V-09b'; Name = 'Cosmos DB';    Value = $cosmos.publicNetworkAccess }
        @{ Id = 'SEC-V-09c'; Name = 'Storage';      Value = $storage.publicNetworkAccess }
    )
    foreach ($p in $paas) {
        Add-Check $p.Id "$($p.Name) 공용 네트워크 차단" ($p.Value -eq 'Disabled') `
            "현재: $($p.Value)"
    }

    $vnetId = $out.vnet_id.value
    Add-Check 'SEC-V-11' 'VNet 주입' (-not [string]::IsNullOrEmpty($vnetId))

    $nsgs = Get-Json @('network', 'nsg', 'list', '--resource-group', $rg)
    $hasDeny = $false
    foreach ($nsg in @($nsgs)) {
        foreach ($rule in @($nsg.securityRules)) {
            if ($rule.access -eq 'Deny' -and $rule.direction -eq 'Inbound' -and $rule.priority -ge 4000) {
                $hasDeny = $true
            }
        }
    }
    Add-Check 'SEC-V-11b' 'NSG 기본 거부 규칙 존재' $hasDeny `
        '명시적 거부 규칙이 없으면 Azure 기본 허용 규칙이 적용됩니다'
} else {
    Write-Warn2 'dev 는 공용 엔드포인트를 쓰므로 네트워크 격리 검사를 건너뜁니다'
}

# ═══════════════════════════════════ 5. 애플리케이션
Write-Step '애플리케이션 상태'

$asaName = ($out.spring_apps_name.value -split '/')[-1]
$apps = Get-Json @('spring', 'app', 'list', '--service', $asaName, '--resource-group', $rg)
$appCount = if ($null -eq $apps) { 0 } else { @($apps).Count }
Add-Check 'APP-01' "애플리케이션 6개 (현재 $appCount)" ($appCount -eq 6)

if ($null -ne $apps) {
    # 공개 엔드포인트는 3개만이어야 한다 — 노출 표면 최소화
    $public = @($apps | Where-Object { $_.properties.public -eq $true })
    Add-Check 'APP-02' "공개 엔드포인트 3개 (현재 $($public.Count))" ($public.Count -eq 3) `
        '내부 서비스가 인터넷에 노출되어 있을 수 있습니다'

    # 앱마다 관리 ID 가 붙어 있는가
    $withIdentity = @($apps | Where-Object { $null -ne $_.identity })
    Add-Check 'APP-03' "모든 앱에 관리 ID 연결 ($($withIdentity.Count)/$appCount)" `
        ($withIdentity.Count -eq $appCount)
}

# ═══════════════════════════════════ 6. 태그 · 비용
Write-Step '태그 · 비용 추적'

if ($null -ne $resources) {
    $required = @('system', 'env', 'owner', 'managedBy')
    $missing = 0
    foreach ($r in $resources) {
        foreach ($t in $required) {
            if ($null -eq $r.tags -or -not $r.tags.PSObject.Properties.Name.Contains($t)) {
                $missing++
                break
            }
        }
    }
    Add-Check 'COST-01' "필수 태그 누락 리소스 없음 (누락 $missing 개)" ($missing -eq 0) `
        '태그가 없으면 비용을 서비스별로 나눌 수 없습니다'
}

$failCount = Save-Results -Env $Env -OutDir (Join-Path $PSScriptRoot '..\검증결과')

Write-Host ''
if ($failCount -eq 0 -and $Env -eq 'stg') {
    Write-Host '✓ stg 검증 통과 — prd 승격 조건을 만족합니다.' -ForegroundColor Green
}
exit $failCount
