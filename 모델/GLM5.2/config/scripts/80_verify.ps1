<#  GLM 80 검증 — 가용성·보안·비용·관측 종합 (06 §5·§6)

    '떴다'가 아니라 '운영해도 되는가'를 판정한다.
#>
[CmdletBinding()]
param([string]$ConfigPath = "$PSScriptRoot\..\env.glm.json")

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$ns = $cfg.k8s.namespace
$app = $cfg.k8s.appName
$results = @()
function Add-V { param($n, $ok, $d) $script:results += [ordered]@{ Name = $n; Status = $(if ($ok) { 'Pass' } else { 'Fail' }); Detail = $d } }

$statePath = "$PSScriptRoot\reports\infra-state.json"
$state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json } else { $null }

Write-Step "가용성"
$dep = kubectl get deploy $app -n $ns -o json 2>$null | ConvertFrom-Json
Add-V 'Ready 복제본 >= 1' ($dep -and $dep.status.readyReplicas -ge 1) ("ready=" + $(if ($dep) { $dep.status.readyReplicas } else { 'n/a' }))
$pdb = kubectl get pdb $app -n $ns -o json 2>$null | ConvertFrom-Json
Add-V 'PodDisruptionBudget 존재' ($null -ne $pdb) ("minAvailable=" + $(if ($pdb) { $pdb.spec.minAvailable } else { '없음' }))

Write-Step "보안 (06 §6)"
$svc = kubectl get svc $app -n $ns -o json 2>$null | ConvertFrom-Json
Add-V 'G-S-01 외부 노출 없음(ClusterIP)' ($svc -and $svc.spec.type -eq 'ClusterIP') ("type=" + $(if ($svc) { $svc.spec.type } else { 'n/a' }))

$np = kubectl get networkpolicy -n $ns -o json 2>$null | ConvertFrom-Json
Add-V 'G-S-02 NetworkPolicy 존재' ($np -and $np.items.Count -ge 1) ("정책 " + $(if ($np) { $np.items.Count } else { 0 }) + "건")

$sa = kubectl get sa $cfg.k8s.serviceAccount -n $ns -o json 2>$null | ConvertFrom-Json
$saClient = if ($sa) { $sa.metadata.annotations.'azure.workload.identity/client-id' } else { $null }
Add-V 'G-S-03 워크로드 ID 주석 치환됨' ($saClient -and $saClient -notmatch 'PLACEHOLDER') ("clientId=" + $(if ($saClient) { '설정됨' } else { '없음' }))

$pod = kubectl get pods -n $ns -l ("app=" + $app) -o jsonpath='{.items[0].metadata.name}' 2>$null
if ($pod) {
    $envClient = kubectl exec $pod -n $ns -- printenv AZURE_CLIENT_ID 2>$null
    $tokenFile = kubectl exec $pod -n $ns -- printenv AZURE_FEDERATED_TOKEN_FILE 2>$null
    Add-V 'G-S-03b 파드에 토큰 주입' ([bool]$envClient -and [bool]$tokenFile) `
        ("AZURE_CLIENT_ID=" + $(if ($envClient) { '주입됨' } else { '없음' }))
} else {
    Add-V 'G-S-03b 파드에 토큰 주입' $false '파드 없음'
}

if ($state -and $state.storageAccount) {
    $shared = az storage account show -g $state.resourceGroup -n $state.storageAccount --query allowSharedKeyAccess -o tsv 2>$null
    Add-V 'G-S-04 저장소 공유 키 차단' ($shared -eq 'false' -or $shared -eq 'False') ("allowSharedKeyAccess=" + $shared)
}

$img = kubectl get deploy $app -n $ns -o jsonpath='{.spec.template.spec.containers[0].image}' 2>$null
Add-V 'G-S-08 불변 이미지 태그' ($img -and $img -notmatch ':latest$') ("image=" + $img)

$sc = if ($dep) { $dep.spec.template.spec.securityContext } else { $null }
Add-V 'G-S-06 비루트 실행' ($sc -and $sc.runAsNonRoot -eq $true) ("runAsNonRoot=" + $(if ($sc) { $sc.runAsNonRoot } else { 'n/a' }))

Write-Step "비용 (06 §5)"
$aksRg = if ($state) { $state.aksResourceGroup } else { $cfg.azure.reuseAksFrom.resourceGroup }
$aksName = if ($state) { $state.aksName } else { $cfg.azure.reuseAksFrom.aksName }
$pool = az aks nodepool show -g $aksRg --cluster-name $aksName -n $cfg.azure.gpu.nodePoolName -o json 2>$null | ConvertFrom-Json
if ($pool) {
    Add-V 'G-C-02a 노드 풀 min-count = 0' ($pool.minCount -eq 0) ("min=" + $pool.minCount + " max=" + $pool.maxCount + " current=" + $pool.count)
    $hasTaint = $pool.nodeTaints -and ($pool.nodeTaints -join ',') -match 'gpu'
    Add-V 'G-C-02b GPU 노드 taint 존재' ([bool]$hasTaint) ("taints=" + ($pool.nodeTaints -join ','))
    Add-V 'Spot 우선순위 적용' ($pool.scaleSetPriority -eq 'Spot') ("priority=" + $pool.scaleSetPriority)
} else {
    Add-V 'GPU 노드 풀 조회' $false '노드 풀을 찾을 수 없습니다'
}

$rgTags = az group show -n $cfg.azure.resourceGroup --query tags -o json 2>$null | ConvertFrom-Json
Add-V 'G-C-05 비용 태그 부착' ($rgTags -and $rgTags.workload) ("workload=" + $(if ($rgTags) { $rgTags.workload } else { '없음' }))

Write-Step "관측"
$mon = az aks show -g $aksRg -n $aksName --query "addonProfiles.omsagent.enabled" -o tsv 2>$null
Add-V 'Container Insights 사용' ($mon -eq 'true') ("enabled=" + $mon)

Write-Step "로그에 프롬프트 본문이 남지 않는가 (G-S-05)"
$logs = kubectl logs -n $ns -l ("app=" + $app) --tail=200 2>$null
$leaked = $logs -and ($logs -match '"messages"' -or $logs -match '"content"\s*:')
Add-V 'G-S-05 프롬프트 본문 미기록' (-not $leaked) `
    $(if ($leaked) { '로그에 요청 본문으로 보이는 내용이 있습니다 — VLLM_LOG_REQUESTS 확인' } else { '최근 200줄에서 탐지 없음' })

$ok = New-GlmReport -Kind 'verify' -Results $results
Write-Host ""
kubectl get deploy,pods,svc,hpa,pdb -n $ns
if (-not $ok) { Write-Err2 '운영 준비 기준 미충족 — 위 [FAIL] 을 확인하세요.'; exit 1 }
Write-Ok 'GLM 운영 준비 검증 통과'
