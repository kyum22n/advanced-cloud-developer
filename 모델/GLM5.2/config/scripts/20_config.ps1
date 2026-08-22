<#  GLM 20 구성 — 저장소·Key Vault·관리 ID·GPU 노드 풀·연합 자격 증명
    실행: pwsh -File .\20_config.ps1 [-Force]

    ⚠️ GPU 노드 풀은 시간당 과금됩니다. min-count 0 이므로 파드가 없으면 노드도 없습니다.
#>
[CmdletBinding()]
param([string]$ConfigPath = "$PSScriptRoot\..\env.glm.json", [switch]$Force)

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$RG = $cfg.azure.resourceGroup
$loc = $cfg.azure.location
$gpu = $cfg.azure.gpu
$suffix = -join ((97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
$tags = @()
$cfg.azure.tags.PSObject.Properties | ForEach-Object { $tags += ("{0}={1}" -f $_.Name, $_.Value) }

Write-Warn2 "GPU 노드 풀을 만듭니다. 파드가 뜨면 시간당 과금이 시작됩니다."
if (-not (Confirm-Destructive -Target ("GLM 인프라 생성 (" + $RG + ")") -Force:$Force)) { exit 0 }

Write-Step "1/6 리소스 그룹"
Invoke-Checked -What 'resource group' -Script { az group create -n $RG -l $loc --tags @tags -o none }

Write-Step "2/6 가중치 저장소 · Key Vault"
$saName = ($cfg.azure.storage.namePrefix + $suffix)
$existing = az storage account list -g $RG --query "[?starts_with(name,'$($cfg.azure.storage.namePrefix)')].name" -o tsv 2>$null | Select-Object -First 1
if ($existing) { $saName = $existing; Write-Info ("저장소 재사용: " + $saName) }
else {
    Invoke-Checked -What 'storage account (공유 키 비활성)' -Script {
        az storage account create -g $RG -n $saName -l $loc `
            --sku $cfg.azure.storage.sku --kind StorageV2 --min-tls-version TLS1_2 `
            --access-tier $cfg.azure.storage.accessTier `
            --allow-shared-key-access false --tags @tags -o none
    }
}
$saId = az storage account show -g $RG -n $saName --query id -o tsv

$kvName = ($cfg.azure.keyVault.namePrefix + '-' + $suffix)
$existingKv = az keyvault list -g $RG --query "[?starts_with(name,'$($cfg.azure.keyVault.namePrefix)')].name" -o tsv 2>$null | Select-Object -First 1
if ($existingKv) { $kvName = $existingKv; Write-Info ("Key Vault 재사용: " + $kvName) }
else {
    Invoke-Checked -What 'key vault' -Script {
        az keyvault create -g $RG -n $kvName -l $loc --enable-rbac-authorization true --tags @tags -o none
    }
}
$kvId = az keyvault show -n $kvName --query id -o tsv

Write-Step "3/6 관리 ID · 최소 권한 역할"
$idName = $cfg.identity.userAssignedName
az identity show -g $RG -n $idName -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Checked -What 'managed identity' -Script { az identity create -g $RG -n $idName -l $loc -o none }
}
$clientId = az identity show -g $RG -n $idName --query clientId -o tsv
$principalId = az identity show -g $RG -n $idName --query principalId -o tsv
Write-Info "관리 ID 준비 — 리소스 단위 최소 권한만 부여합니다"

# 가중치는 '읽기'만 필요하다 — 쓰기 권한을 주면 침해 시 모델이 교체될 수 있다
foreach ($pair in @(
    @{ role = 'Storage Blob Data Reader'; scope = $saId },
    @{ role = 'Key Vault Secrets User'; scope = $kvId }
)) {
    az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
        --role $pair.role --scope $pair.scope -o none 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok ("역할 부여: " + $pair.role) }
    else { Write-Info ("역할 이미 존재하거나 권한 부족: " + $pair.role) }
}

Write-Step "4/6 GPU 노드 풀 (Spot · taint · min 0)"
$aksRg = if ($cfg.azure.reuseAksFrom.resourceGroup) { $cfg.azure.reuseAksFrom.resourceGroup } else { $RG }
$aksName = $cfg.azure.reuseAksFrom.aksName
az aks show -g $aksRg -n $aksName -o none 2>$null
if ($LASTEXITCODE -ne 0) { throw "AKS 클러스터를 찾을 수 없습니다: $aksRg/$aksName — env.glm.json 의 reuseAksFrom 을 확인하세요." }

$poolExists = az aks nodepool show -g $aksRg --cluster-name $aksName -n $gpu.nodePoolName -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Info "GPU 노드 풀 생성 (5~10분)"
    # taint 와 min-count 0 은 세트다 — taint 가 없으면 일반 파드가 남아 축소되지 않는다
    $a = @('aks', 'nodepool', 'add', '-g', $aksRg, '--cluster-name', $aksName, '-n', $gpu.nodePoolName,
        '--node-vm-size', $gpu.sku, '--node-count', '0',
        '--enable-cluster-autoscaler', '--min-count', $gpu.minCount, '--max-count', $gpu.maxCount,
        '--priority', $gpu.priority, '--eviction-policy', $gpu.evictionPolicy,
        '--spot-max-price', $gpu.spotMaxPrice,
        '--node-taints', $gpu.taint, '--labels', $gpu.label,
        '--mode', 'User', '--only-show-errors', '-o', 'none')
    if ($gpu.osDiskType) { $a += @('--node-osdisk-type', $gpu.osDiskType) }
    Invoke-Checked -What 'gpu nodepool add' -Script { az @a }
} else {
    Write-Info ("GPU 노드 풀 재사용: " + $gpu.nodePoolName)
}

if ($cfg.azure.onDemandStandby.enabled) {
    $od = $cfg.azure.onDemandStandby
    az aks nodepool show -g $aksRg --cluster-name $aksName -n $od.nodePoolName -o none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "온디맨드 예비 노드 풀 생성 (Spot 회수 대비)"
        Invoke-Checked -What 'on-demand standby nodepool' -Script {
            az aks nodepool add -g $aksRg --cluster-name $aksName -n $od.nodePoolName `
                --node-vm-size $gpu.sku --node-count $od.minCount `
                --enable-cluster-autoscaler --min-count $od.minCount --max-count $od.maxCount `
                --node-taints $gpu.taint --labels $gpu.label --mode User -o none
        }
    }
}

Write-Step "5/6 kubeconfig · 워크로드 ID 연합"
Invoke-Checked -What 'kubeconfig' -Script { az aks get-credentials -g $aksRg -n $aksName --overwrite-existing }
$oidc = az aks show -g $aksRg -n $aksName --query oidcIssuerProfile.issuerUrl -o tsv
if (-not $oidc) { throw "OIDC 발급자가 활성화되어 있지 않습니다 — az aks update --enable-oidc-issuer 를 먼저 실행하세요." }

$ns = $cfg.k8s.namespace
$sa = $cfg.k8s.serviceAccount
$subject = "system:serviceaccount:{0}:{1}" -f $ns, $sa
az identity federated-credential show -g $RG --identity-name $idName -n $cfg.identity.federatedCredentialName -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Checked -What 'federated credential' -Script {
        az identity federated-credential create -g $RG --identity-name $idName `
            -n $cfg.identity.federatedCredentialName `
            --issuer $oidc --subject $subject --audiences $cfg.identity.audience -o none
    }
}
Write-Info ("연합 subject: " + $subject)

Write-Step "6/6 매니페스트 치환값 기록"
$tenantId = az account show --query tenantId -o tsv
$blobUrl = "https://{0}.blob.core.windows.net/{1}" -f $saName, $cfg.azure.storage.container
$state = [ordered]@{
    resourceGroup = $RG; aksResourceGroup = $aksRg; aksName = $aksName
    storageAccount = $saName; blobBaseUrl = $blobUrl; keyVaultName = $kvName
    identityName = $idName; clientId = $clientId; principalId = $principalId
    tenantId = $tenantId; oidcIssuer = $oidc; federatedSubject = $subject
    gpuNodePool = $gpu.nodePoolName; gpuSku = $gpu.sku
    createdAt = (Get-Date).ToString('s')
}
New-Item -ItemType Directory -Force "$PSScriptRoot\reports" | Out-Null
$state | ConvertTo-Json | Out-File "$PSScriptRoot\reports\infra-state.json" -Encoding utf8

Write-Ok "구성 완료"
Write-Info ("가중치 업로드 대상: " + $blobUrl)
Write-Info "다음: 가중치를 업로드한 뒤 .\30_build.ps1 (05 배포 가이드 §3 참조)"
