<#  GLM 90 정리 — 비싼 것부터 지운다
    ⚠️ 되돌릴 수 없습니다. GPU 노드 풀이 비용의 대부분이므로 이것부터 삭제합니다.
#>
[CmdletBinding()]
param([string]$ConfigPath = "$PSScriptRoot\..\env.glm.json", [switch]$Force, [switch]$KeepResourceGroup)

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$statePath = "$PSScriptRoot\reports\infra-state.json"
$state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json } else { $null }
$aksRg = if ($state) { $state.aksResourceGroup } else { $cfg.azure.reuseAksFrom.resourceGroup }
$aksName = if ($state) { $state.aksName } else { $cfg.azure.reuseAksFrom.aksName }

Write-Step "삭제 대상"
Write-Host "  1. GPU 노드 풀      : $aksRg / $aksName / $($cfg.azure.gpu.nodePoolName)   ← 비용의 대부분"
if ($cfg.azure.onDemandStandby.enabled) { Write-Host "  2. 예비 노드 풀     : $($cfg.azure.onDemandStandby.nodePoolName)" }
Write-Host "  3. 네임스페이스     : $($cfg.k8s.namespace)"
if (-not $KeepResourceGroup) {
    Write-Host "  4. 리소스 그룹      : $($cfg.azure.resourceGroup)  (가중치 저장소 · Key Vault 포함)"
}

if (-not (Confirm-Destructive -Target 'GLM 리소스 삭제' -Force:$Force)) { exit 0 }

Write-Step "GPU 노드 풀 삭제 (과금 중단)"
az aks nodepool delete -g $aksRg --cluster-name $aksName -n $cfg.azure.gpu.nodePoolName --no-wait 2>$null
Write-Ok 'GPU 노드 풀 삭제 요청 (백그라운드 진행)'

if ($cfg.azure.onDemandStandby.enabled) {
    az aks nodepool delete -g $aksRg --cluster-name $aksName -n $cfg.azure.onDemandStandby.nodePoolName --no-wait 2>$null
    Write-Ok '예비 노드 풀 삭제 요청'
}

Write-Step "네임스페이스 삭제"
kubectl delete namespace $cfg.k8s.namespace --ignore-not-found 2>$null
Write-Ok '네임스페이스 삭제'

if (-not $KeepResourceGroup) {
    Write-Step "리소스 그룹 삭제"
    az group delete -n $cfg.azure.resourceGroup --yes --no-wait 2>$null
    Write-Ok '리소스 그룹 삭제 요청 (10~20분 소요)'
    if ($state -and $state.keyVaultName) {
        Write-Warn2 ("Key Vault 는 소프트 삭제 상태로 남습니다. 같은 이름 재사용 시: az keyvault purge --name " + $state.keyVaultName)
    }
}

Write-Step "확인 방법"
Write-Host "  kubectl get nodes -l workload=llm"
Write-Host ("  az aks nodepool list -g {0} --cluster-name {1} -o table" -f $aksRg, $aksName)
Write-Host "  Azure Portal → 비용 분석 → 태그 workload=llm"
Write-Ok '정리 완료'
