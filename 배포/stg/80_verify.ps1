<#  stg 검증 — GitOps 상태(Synced/Healthy)와 드리프트 자동 복구 확인
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\80_verify.ps1 [-Force]
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.stg.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath
$RG  = $cfg.azure.resourceGroup

Write-Step "stg 배포 검증 — GitOps 관점"
$ns = $cfg.app.namespace
$ans = $cfg.argocd.namespace
$appName = $cfg.argocd.appName
$base = $cfg.test.baseUrl
$results = @()
function Add-V { param($n,$ok,$d) $script:results += [ordered]@{ Name=$n; Status=$(if($ok){'Pass'}else{'Fail'}); Detail=$d } }

# 1) Argo CD Application 상태
$appJson = kubectl get application $appName -n $ans -o json 2>$null | ConvertFrom-Json
$sync = if ($appJson) { $appJson.status.sync.status } else { 'n/a' }
$health = if ($appJson) { $appJson.status.health.status } else { 'n/a' }
Add-V 'Argo CD sync = Synced'   ($sync -eq 'Synced')     ("sync=$sync")
Add-V 'Argo CD health = Healthy'($health -eq 'Healthy')  ("health=$health")

# 2) 워크로드 상태
$dep = kubectl get deploy $cfg.app.name -n $ns -o json 2>$null | ConvertFrom-Json
Add-V ("readyReplicas >= " + $cfg.app.replicas) ($dep -and $dep.status.readyReplicas -ge $cfg.app.replicas) ("ready=" + $(if($dep){$dep.status.readyReplicas}else{'n/a'}))

# 3) 배포된 이미지가 Git 의 태그와 일치하는가 (GitOps 핵심 검증)
$expected = $null
if (Test-Path "$PSScriptRoot\reports\last-build.json") { $expected = (Get-Content "$PSScriptRoot\reports\last-build.json" -Raw | ConvertFrom-Json).tag }
$actualImg = kubectl get deploy $cfg.app.name -n $ns -o jsonpath='{.spec.template.spec.containers[0].image}' 2>$null
Add-V '배포 이미지 = 최신 빌드 태그' ($expected -and $actualImg -like ("*:" + $expected)) ("image=$actualImg expect=*:$expected")

# 4) 엔드포인트
if ($base) { foreach ($ep in @('/healthz','/readyz','/version')) { Add-V ("엔드포인트 " + $ep) (Test-HttpOk -Url ($base + $ep)) ($base + $ep) } }

# ── 아이덴티티 전제 (prd 에서 처음 만나지 않도록 stg 에서 미리 확인) ──
$rg = $cfg.azure.resourceGroup
$oidcOn = az aks show -g $rg -n $cfg.azure.aks.name --query oidcIssuerProfile.enabled -o tsv 2>$null
Add-V 'AKS OIDC 발급자 사용(워크로드 ID 전제)' ($oidcOn -eq 'true') ("oidcIssuerEnabled=" + $oidcOn)
$wiOn = az aks show -g $rg -n $cfg.azure.aks.name --query securityProfile.workloadIdentity.enabled -o tsv 2>$null
Add-V 'AKS 워크로드 ID 애드온 사용' ($wiOn -eq 'true') ("workloadIdentityEnabled=" + $wiOn)
$kubeletId = az aks show -g $rg -n $cfg.azure.aks.name --query identityProfile.kubeletidentity.clientId -o tsv 2>$null
Add-V 'kubelet 관리 ID 로 ACR pull(imagePullSecret 없음)' ([bool]$kubeletId) ("kubeletClientId=" + $(if($kubeletId){'있음'}else{'없음'}))
$ips = kubectl get deploy $($cfg.app.name) -n $ns -o jsonpath='{.spec.template.spec.imagePullSecrets}' 2>$null
Add-V 'imagePullSecret 미사용' ([string]::IsNullOrWhiteSpace($ips)) ("imagePullSecrets=" + $(if($ips){$ips}else{'없음'}))

# 5) 드리프트 자동 복구(selfHeal) 확인 — 레플리카를 임의 변경 후 되돌아오는지
if ($appJson -and $appJson.spec.syncPolicy.automated.selfHeal) {
    Write-Info '드리프트 테스트: 레플리카를 1로 바꾼 뒤 Argo CD 가 되돌리는지 확인합니다.'
    kubectl scale deploy/$($cfg.app.name) -n $ns --replicas=1 -o none 2>$null
    $restored = $false
    try {
        Wait-Condition -What 'selfHeal 복구' -TimeoutSec 240 -IntervalSec 10 -Condition {
            $d = kubectl get deploy $cfg.app.name -n $ns -o json 2>$null | ConvertFrom-Json
            return ($d.spec.replicas -eq $cfg.app.replicas)
        }
        $restored = $true
    } catch { $restored = $false }
    Add-V 'selfHeal: 수동 변경이 Git 상태로 자동 복구' $restored ("목표 replicas=" + $cfg.app.replicas)
} else {
    Add-V 'selfHeal 활성화' $false 'syncPolicy.automated.selfHeal 미설정'
}

$ok = New-TestReport -Env 'stg' -Kind 'verify' -Results $results -OutDir "$PSScriptRoot\reports"
Write-Host ""
kubectl get application $appName -n $ans 2>$null
kubectl get all -n $ns
if (-not $ok) { exit 1 }
Write-Ok 'stg 검증 통과 — GitOps 가 의도대로 동작합니다.'
