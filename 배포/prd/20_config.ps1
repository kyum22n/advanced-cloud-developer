<#  prd 구성 — 네트워크·PaaS 데이터·보안·관측·AKS 를 의존 순서대로 생성
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\20_config.ps1 [-Force]
    ⚠️ 운영 환경 스크립트입니다. 파괴적 작업은 반드시 확인을 거칩니다.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.prd.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
. "$PSScriptRoot\..\common\identity.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath
$RG  = $cfg.azure.resourceGroup

Write-Warn2 "운영 등급 리소스를 생성합니다. 시간당 과금이 크며 생성에 15~25분이 걸립니다."
if (-not (Confirm-Destructive -Target ("운영 리소스 생성 (" + $RG + ")") -Force:$Force)) { exit 0 }

$loc = $cfg.azure.location
$net = $cfg.azure.network
$pg  = $cfg.azure.data.postgres
$suffix = -join ((97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })

Write-Step "1/6 리소스 그룹 · 네트워크 (참조당하는 것부터)"
Invoke-Checked -What 'resource group' -Script { az group create -n $RG -l $loc -o none }
$vnetExists = az network vnet show -g $RG -n $net.vnetName -o none 2>$null; $vnetExists = ($LASTEXITCODE -eq 0)
if (-not $vnetExists) {
    Invoke-Checked -What 'vnet + aks subnet' -Script {
        az network vnet create -g $RG -n $net.vnetName -l $loc `
            --address-prefixes $net.vnetCidr `
            --subnet-name $net.aksSubnetName --subnet-prefixes $net.aksSubnetCidr -o none
    }
    Invoke-Checked -What 'data subnet' -Script {
        az network vnet subnet create -g $RG --vnet-name $net.vnetName -n $net.dataSubnetName `
            --address-prefixes $net.dataSubnetCidr -o none
    }
}

Write-Step "2/6 관측 (Log Analytics · Application Insights)"
$law = $cfg.azure.observability.logAnalytics
$lawId = az monitor log-analytics workspace show -g $RG -n $law --query id -o tsv 2>$null
if (-not $lawId) {
    Invoke-Checked -What 'log analytics' -Script { az monitor log-analytics workspace create -g $RG -n $law -l $loc -o none }
    $lawId = az monitor log-analytics workspace show -g $RG -n $law --query id -o tsv
}
az extension add --name application-insights --only-show-errors 2>$null | Out-Null
$aiExists = az monitor app-insights component show -g $RG --app $cfg.azure.observability.appInsights -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Checked -What 'app insights' -Script {
        az monitor app-insights component create -g $RG --app $cfg.azure.observability.appInsights -l $loc --kind web --workspace $law -o none
    }
}

Write-Step "3/6 보안 (Key Vault · 워크로드 ID)"
$kvName = ($cfg.azure.data.keyvault.namePrefix + '-' + $suffix)
$kvPrefix = $cfg.azure.data.keyvault.namePrefix
$existingKv = (az keyvault list -g $RG -o json 2>$null | ConvertFrom-Json | Where-Object { $_.name -like "$kvPrefix*" } | Select-Object -First 1).name
if ($existingKv) { $kvName = $existingKv; Write-Info ("Key Vault 재사용: " + $kvName) }
else { Invoke-Checked -What 'key vault' -Script { az keyvault create -g $RG -n $kvName -l $loc --enable-rbac-authorization true -o none } }

# 워크로드 ID 로 쓸 사용자 할당 관리 ID — 앱이 '비밀번호 없이' Azure 에 접근하는 주체
$idName = $cfg.identity.userAssignedName
if (-not $idName) { $idName = $cfg.app.workloadIdentityName }   # 하위 호환
$mi = New-UserAssignedIdentity -ResourceGroup $RG -Name $idName -Location $loc
$idClientId  = $mi.clientId
$idPrincipal = $mi.principalId
Write-Info "관리 ID 준비 완료 — 이 주체에 '리소스 단위 최소 권한'만 부여합니다"

# Key Vault 는 '읽기' 역할만 준다 (Secrets Officer 가 아니라 Secrets User)
$kvId = az keyvault show -n $kvName --query id -o tsv
Grant-AzRole -PrincipalId $idPrincipal -Role 'Key Vault Secrets User' -Scope $kvId | Out-Null

# 배포 스크립트를 실행하는 로그인 계정 자신에게는 '쓰기'(Secrets Officer)가 필요하다 —
# RBAC 인가 Key Vault라 앱 관리 ID(읽기 전용)와 별개로, 비밀을 실제로 넣는 이 계정에 부여해야 한다.
# (2026-08-29 최종검토: 이 역할이 없어 az keyvault secret set 이 ForbiddenByRbac 로 실패하는데도
#  스크립트가 오류를 확인하지 않고 무조건 성공으로 표시하던 버그를 함께 수정)
$callerId = az ad signed-in-user show --query id -o tsv 2>$null
if ($callerId) {
    az role assignment create --assignee-object-id $callerId --assignee-principal-type User `
        --role 'Key Vault Secrets Officer' --scope $kvId -o none 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok '역할 부여: Key Vault Secrets Officer (로그인 계정)' }
    else { Write-Warn2 '로그인 계정에 Key Vault Secrets Officer 부여 실패(이미 있을 수 있음) — 계속 진행' }
} else { Write-Warn2 '로그인 계정 조회 실패 — Key Vault 쓰기 역할을 부여하지 못했습니다.' }
Write-Info 'Key Vault RBAC 역할 전파 대기 (30초)'
Start-Sleep -Seconds 30

$skipPaasData = [bool]$cfg.skipPaasData
$pgHost = $null; $redisHost = $null; $saName = $null; $pwAuth = 'Enabled'
if (-not $skipPaasData) {
    Write-Step "4/6 PaaS 데이터 (PostgreSQL 유연한 서버 · Redis · Storage)"
    $dbPw = [Environment]::GetEnvironmentVariable($pg.adminPasswordEnvVar)
    if (-not $dbPw) { throw ("환경 변수 {0} 가 필요합니다." -f $pg.adminPasswordEnvVar) }
    $pwAuth = $cfg.identity.postgresPasswordAuth
    if (-not $pwAuth) { $pwAuth = 'Enabled' }
    if ($pwAuth -eq 'Enabled') {
        Write-Warn2 "PostgreSQL 암호 인증이 켜져 있습니다(실습 호환). 운영 목표 상태는 'Disabled' — 앱이 토큰 인증으로 전환된 뒤 바꾸세요."
    }

    $pgExists = az postgres flexible-server show -g $RG -n $pg.name -o none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "PostgreSQL 유연한 서버 생성 (영역 중복 HA · 5~10분 소요)"
        Invoke-Checked -What 'postgres flexible-server create' -Script {
            az postgres flexible-server create -g $RG -n $pg.name -l $loc `
                --tier $pg.tier --sku-name $pg.sku --storage-size $pg.storageGb --version $pg.version `
                --high-availability $pg.haMode --backup-retention $pg.backupRetentionDays `
                --admin-user $pg.adminUser --admin-password $dbPw `
                --active-directory-auth Enabled --password-auth $pwAuth `
                --public-access None --yes -o none
        }
    }
    Invoke-Checked -What 'database 생성' -Script {
        az postgres flexible-server db create -g $RG -s $pg.name -d $pg.database -o none 2>$null
    }

    $redis = $cfg.azure.data.redis
    $redisExists = az redis show -g $RG -n $redis.name -o none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Checked -What 'redis create' -Script {
            az redis create -g $RG -n $redis.name -l $loc --sku $redis.sku --vm-size $redis.vmSize `
                --minimum-tls-version 1.2 -o none
        }
    }

    $saName = ($cfg.azure.data.storage.namePrefix + $suffix)
    $saPrefix = $cfg.azure.data.storage.namePrefix
    $existingSa = (az storage account list -g $RG -o json 2>$null | ConvertFrom-Json | Where-Object { $_.name -like "$saPrefix*" } | Select-Object -First 1).name
    if ($existingSa) { $saName = $existingSa } else {
        Invoke-Checked -What 'storage account' -Script {
            az storage account create -g $RG -n $saName -l $loc --sku $cfg.azure.data.storage.sku `
                --kind StorageV2 --min-tls-version TLS1_2 --allow-shared-key-access false -o none
        }
    }

    Write-Step "4-1/6 비밀번호 없는 데이터 접근 (Entra ID 인증 · 최소 권한 역할)"
    # ① PostgreSQL — 토큰으로 접속할 수 있게 한다
    if ($cfg.identity.passwordless.postgres) {
        Enable-PostgresEntraAuth -ResourceGroup $RG -Server $pg.name `
            -PrincipalId $idPrincipal -DisplayName $idName -PasswordAuth $pwAuth
    }
    # ② Redis — 액세스 키가 아니라 Entra 주체로 접근한다
    if ($cfg.identity.passwordless.redis) {
        Grant-RedisDataAccess -ResourceGroup $RG -Cache $redis.name `
            -PrincipalId $idPrincipal -Alias $idName -Policy 'Data Contributor'
    }
    # ③ Storage — 공유 키는 이미 비활성. 데이터 평면 역할을 부여한다
    if ($cfg.identity.passwordless.storage) {
        $saId = az storage account show -g $RG -n $saName --query id -o tsv
        Grant-AzRole -PrincipalId $idPrincipal -Role 'Storage Blob Data Contributor' -Scope $saId | Out-Null
    }
} else {
    Write-Warn2 "skipPaasData=true — myapp이 쓰지 않는 PostgreSQL·Redis·Storage 생성을 생략합니다(2026-08-29 최종검토, 사용자 승인)."
}
# ACR — AKS kubelet 관리 ID 가 pull 한다(--attach-acr). 앱 관리 ID 에도 pull 만 명시 부여(skipPaasData 무관)
if ($cfg.identity.passwordless.acr) {
    $acrId = az acr show -n $cfg.azure.acrName -g $RG --query id -o tsv 2>$null
    if ($acrId) { Grant-AzRole -PrincipalId $idPrincipal -Role 'AcrPull' -Scope $acrId | Out-Null }
}

Write-Step "5/6 비밀을 Key Vault 에 저장 (값은 화면에 출력하지 않음)"
$secrets = @()
if (-not $skipPaasData) {
    $pgHost = az postgres flexible-server show -g $RG -n $pg.name --query fullyQualifiedDomainName -o tsv
    $redisHost = az redis show -g $RG -n $redis.name --query hostName -o tsv
    # 비밀은 '필요한 것만' 넣는다 — 토큰으로 대체된 값은 애초에 저장하지 않는다
    $secrets += @(
        @{n='db-host';   v=$pgHost},
        @{n='db-user';   v=$(if ($pwAuth -eq 'Disabled') { $idName } else { $pg.adminUser })},
        @{n='redis-host';v=$redisHost}
    )
    if ($pwAuth -eq 'Enabled') {
        $secrets += @{n='db-password'; v=$dbPw}
    } else {
        Write-Info "암호 인증 비활성 — db-password 를 Key Vault 에 저장하지 않습니다(토큰 인증 사용)"
        az keyvault secret delete --vault-name $kvName --name 'db-password' -o none 2>$null
    }
} else {
    Write-Info "skipPaasData=true — db-host/db-user/db-password/redis-host 비밀 저장을 생략합니다(myapp 미사용)."
}

# myapp 자체가 쓰는 비밀값 — 환경 변수로만 받는다. 없으면 빈 문자열로 저장한다(앱이 "미설정"으로 정상 처리).
$githubToken  = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN')
$notionToken  = [Environment]::GetEnvironmentVariable('NOTION_TOKEN')
$notionPageId = [Environment]::GetEnvironmentVariable('NOTION_PARENT_PAGE_ID')
if (-not $githubToken)  { Write-Warn2 '환경 변수 GITHUB_TOKEN 이 없어 빈 값으로 저장합니다.' }
if (-not $notionToken)  { Write-Warn2 '환경 변수 NOTION_TOKEN 이 없어 빈 값으로 저장합니다.' }
if (-not $notionPageId) { Write-Warn2 '환경 변수 NOTION_PARENT_PAGE_ID 가 없어 빈 값으로 저장합니다.' }
$secrets += @{n='github-token'; v=$(if ($githubToken) { $githubToken } else { ' ' })}
$secrets += @{n='notion-token'; v=$(if ($notionToken) { $notionToken } else { ' ' })}
$secrets += @{n='notion-parent-page-id'; v=$(if ($notionPageId) { $notionPageId } else { ' ' })}

foreach ($s in $secrets) {
    az keyvault secret set --vault-name $kvName --name $s.n --value $s.v --output none
    if ($LASTEXITCODE -eq 0) { Write-Ok ("Key Vault 비밀 저장: " + $s.n) }
    else { throw ("Key Vault 비밀 저장 실패: " + $s.n + " (exit=" + $LASTEXITCODE + ")") }
}

Write-Step "6/6 AKS (영역 분산 · 시스템/사용자 노드 풀 분리 · 애드온)"
$aks = $cfg.azure.aks
$subnetId = az network vnet subnet show -g $RG --vnet-name $net.vnetName -n $net.aksSubnetName --query id -o tsv
$aksExists = az aks show -g $RG -n $aks.name -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Info "AKS 생성 (10~15분 소요)"
    $a = @('aks','create','-g',$RG,'-n',$aks.name,'-l',$loc,
        '--tier',$aks.tier,
        '--node-count',$aks.systemNodeCount,'--node-vm-size',$aks.systemNodeSize,
        '--nodepool-name','system','--zones') + $aks.zones + @(
        '--vnet-subnet-id',$subnetId,
        '--network-plugin',$aks.networkPlugin,'--network-plugin-mode',$aks.networkPluginMode,
        '--enable-oidc-issuer','--enable-workload-identity',
        '--enable-addons','monitoring,azure-keyvault-secrets-provider,web_application_routing',
        '--workspace-resource-id',$lawId,
        '--enable-managed-identity','--attach-acr',$cfg.azure.acrName,
        '--generate-ssh-keys','--only-show-errors','-o','none')
    # ACR 이 아직 없으면 먼저 만든다
    az acr show -n $cfg.azure.acrName -g $RG -o none 2>$null
    if ($LASTEXITCODE -ne 0) { az acr create -g $RG -n $cfg.azure.acrName --sku Standard -l $loc -o none }
    Invoke-Checked -What 'aks create' -Script { az @a }
}
$userPoolExists = az aks nodepool show -g $RG --cluster-name $aks.name -n user -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    az aks nodepool add -g $RG --cluster-name $aks.name -n user `
        --node-count $aks.userNodeCount --node-vm-size $aks.userNodeSize `
        --zones $aks.zones[0] $aks.zones[1] $aks.zones[2] `
        --enable-cluster-autoscaler --min-count $aks.userNodeMin --max-count $aks.userNodeMax `
        --mode User -o none
    if ($LASTEXITCODE -eq 0) { Write-Ok '사용자 노드 풀 추가 완료' }
    else {
        Write-Warn2 "사용자 노드 풀 추가 실패(vCPU 쿼터 소진, 2026-08-29 확인) — 시스템 노드 풀에 워크로드를 배포합니다."
    }
} else { Write-Info '사용자 노드 풀 이미 존재 — 생성 생략' }
if ($cfg.azure.observability.enableManagedPrometheus) {
    az aks update -g $RG -n $aks.name --enable-azure-monitor-metrics -o none 2>$null
}
Invoke-Checked -What 'kubeconfig' -Script { az aks get-credentials -g $RG -n $aks.name --overwrite-existing }

Write-Step "워크로드 ID 연합 자격 증명 · 매니페스트 치환값 기록"
$oidc = Get-AksOidcIssuer -ResourceGroup $RG -Name $aks.name
$fcName = $cfg.identity.federatedCredentialName
if (-not $fcName) { $fcName = 'fc-myapp' }
$subject = New-FederatedCredential -ResourceGroup $RG -IdentityName $idName -Name $fcName `
    -Issuer $oidc -Namespace $cfg.app.namespace -ServiceAccount $cfg.app.serviceAccount
Write-Info ("연합 subject: " + $subject)

$tenantId = az account show --query tenantId -o tsv
$state = @{
    keyvaultName = $kvName; clientId = $idClientId; tenantId = $tenantId
    postgresHost = $pgHost; redisHost = $redisHost; storageAccount = $saName
    acrLoginServer = ("{0}.azurecr.io" -f $cfg.azure.acrName); oidcIssuer = $oidc
    identityName = $idName; identityPrincipalId = $idPrincipal
    federatedSubject = $subject; postgresPasswordAuth = $pwAuth
    createdAt = (Get-Date).ToString('s')
}
New-Item -ItemType Directory -Force "$PSScriptRoot\reports" | Out-Null
$state | ConvertTo-Json | Out-File "$PSScriptRoot\reports\infra-state.json" -Encoding utf8

Write-Ok "prd 구성 완료 — 다음: .\30_build.ps1"
Write-Info ("Key Vault: {0} · 워크로드 ID clientId: {1}" -f $kvName, $idClientId)
Write-Info "아이덴티티 태세는 .\80_verify.ps1 이 실제 리소스를 조회해 검증합니다."
