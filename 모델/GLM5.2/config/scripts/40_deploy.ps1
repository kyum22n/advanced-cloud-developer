<#  GLM 40 배포 — 매니페스트 치환·적용·모델 로딩 대기
    ⚠️ 모델 로딩에 수 분이 걸린다. rollout 타임아웃을 넉넉히 잡는다.
#>
[CmdletBinding()]
param([string]$ConfigPath = "$PSScriptRoot\..\env.glm.json", [int]$TimeoutSeconds = 1800)

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$model = Get-GlmModel
$ns = $cfg.k8s.namespace

$statePath = "$PSScriptRoot\reports\infra-state.json"
$buildPath = "$PSScriptRoot\reports\last-build.json"
if (-not (Test-Path $statePath)) { throw "infra-state.json 이 없습니다 — 20_config.ps1 을 먼저 실행하세요." }
if (-not (Test-Path $buildPath)) { throw "last-build.json 이 없습니다 — 30_build.ps1 을 먼저 실행하세요." }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$build = Get-Content $buildPath -Raw | ConvertFrom-Json

Write-Step "매니페스트 치환"
$src = (Resolve-Path "$PSScriptRoot\..\k8s").Path
$dst = Join-Path $env:TEMP ("glm-k8s-" + (Get-Date -Format 'yyyyMMddHHmmss'))
Copy-Item $src $dst -Recurse
$map = @{
    'CLIENT_ID_PLACEHOLDER'        = $state.clientId
    'KEYVAULT_NAME_PLACEHOLDER'    = $state.keyVaultName
    'TENANT_ID_PLACEHOLDER'        = $state.tenantId
    'ACR_LOGIN_SERVER_PLACEHOLDER' = $build.loginServer
    'TAG_PLACEHOLDER'              = $build.tag
    'MODEL_ID_PLACEHOLDER'         = $model.modelId
    'MODEL_BLOB_URL_PLACEHOLDER'   = ($state.blobBaseUrl + '/' + $model.modelId)
}
Get-ChildItem $dst -Filter *.yaml | ForEach-Object {
    $text = Get-Content $_.FullName -Raw -Encoding UTF8
    foreach ($k in $map.Keys) { $text = $text.Replace($k, [string]$map[$k]) }
    $text | Out-File $_.FullName -Encoding utf8 -NoNewline
}
Write-Ok ("치환 완료: " + $dst)

Write-Step "적용"
Invoke-Checked -What 'kubectl apply -k' -Script { kubectl apply -k $dst }

Write-Step "모델 로딩 대기 (수 분 소요)"
Write-Info "Pending = GPU 노드 대기 · Running(0/1) = 가중치 로딩 중"
kubectl rollout status ("deploy/" + $cfg.k8s.appName) -n $ns --timeout=("{0}s" -f $TimeoutSeconds)
if ($LASTEXITCODE -ne 0) {
    Write-Err2 "롤아웃이 완료되지 않았습니다. 아래를 확인하세요:"
    kubectl get pods -n $ns -o wide
    kubectl describe pod -n $ns -l ("app=" + $cfg.k8s.appName) | Select-String -Pattern 'Insufficient|FailedScheduling|taint|Warning' | Select-Object -First 20
    exit 1
}

Write-Step "배포 확인"
kubectl get deploy,pods,svc,hpa,pdb -n $ns
$ready = kubectl get deploy $cfg.k8s.appName -n $ns -o jsonpath='{.status.readyReplicas}' 2>$null
Write-Ok ("준비된 복제본: " + $ready)
Write-Info ("접속 확인: kubectl port-forward -n {0} svc/{1} 8000:8000" -f $ns, $cfg.k8s.appName)
Write-Info "다음: .\50_smoke.ps1"
