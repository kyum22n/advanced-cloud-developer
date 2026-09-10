<#  prd 배포 — 매니페스트 치환 → Git 승격 커밋 → Argo CD 수동 Sync(사람 승인)
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\40_deploy.ps1 [-Force]
    ⚠️ 운영 환경 스크립트입니다. 파괴적 작업은 반드시 확인을 거칩니다.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.prd.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath
$RG  = $cfg.azure.resourceGroup

Write-Step "운영 배포 — 승격(promotion) 절차"

$buildFile = "$PSScriptRoot\reports\last-build.json"
$stateFile = "$PSScriptRoot\reports\infra-state.json"
if (-not (Test-Path $buildFile)) { Write-Err2 '빌드 기록이 없습니다. .\30_build.ps1 을 먼저 실행하세요.'; exit 1 }
if (-not (Test-Path $stateFile)) { Write-Err2 '인프라 상태 기록이 없습니다. .\20_config.ps1 을 먼저 실행하세요.'; exit 1 }
$b = Get-Content $buildFile -Raw | ConvertFrom-Json
$st = Get-Content $stateFile -Raw | ConvertFrom-Json

Write-Info ("승격 대상 이미지: {0}/{1}:{2}" -f $b.registry, $b.repository, $b.tag)
if (-not (Confirm-Destructive -Target ("운영 배포 (태그 " + $b.tag + ")") -Force:$Force)) { exit 0 }

Write-Step "1/4 매니페스트 치환 (Key Vault·워크로드 ID·테넌트)"
foreach ($f in @('base\serviceaccount.yaml','base\secretprovider.yaml','base\configmap.yaml')) {
    $p = Join-Path "$PSScriptRoot\config\k8s" $f
    $t = Get-Content $p -Raw -Encoding UTF8
    $t = $t.Replace('CLIENT_ID_PLACEHOLDER', $st.clientId)
    $t = $t.Replace('KEYVAULT_NAME_PLACEHOLDER', $st.keyvaultName)
    $t = $t.Replace('TENANT_ID_PLACEHOLDER', $st.tenantId)
    $t | Out-File $p -Encoding utf8 -NoNewline
    Write-Ok ("치환 완료: " + $f)
}
$kust = "$PSScriptRoot\config\k8s\overlays\prd\kustomization.yaml"
$k = Get-Content $kust -Raw -Encoding UTF8
$k = $k -replace 'newName: .*', ("newName: {0}/{1}" -f $b.registry, $b.repository)
$k = $k -replace 'newTag: .*',  ("newTag: " + $b.tag)
$k | Out-File $kust -Encoding utf8 -NoNewline
Write-Ok ("overlay 태그 갱신: " + $b.tag)

Write-Step "2/4 Git 승격 커밋"
Push-Location $RepoRoot
try {
    git rev-parse --is-inside-work-tree 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        git add -- "배포/prd/config/k8s" 2>$null
        if (git diff --cached --name-only) {
            Invoke-Checked -What 'git commit' -Script { git commit -m ("release(prd): promote {0}" -f $b.tag) --no-verify }
            if (git remote) { Invoke-Checked -What 'git push' -Script { git push } }
            else { Write-Warn2 '원격 저장소 없음 — Argo CD 가 변경을 볼 수 없습니다.' }
        } else { Write-Info '변경 없음(동일 태그).' }
    } else { Write-Warn2 'Git 저장소가 아니어서 커밋을 건너뜁니다.' }
} finally { Pop-Location }

Write-Step "3/4 Argo CD Application 등록 (운영은 자동 동기화 없음)"
$ans = $cfg.argocd.namespace
kubectl create namespace $ans --dry-run=client -o yaml | kubectl apply -f -
if (-not (kubectl get deploy argocd-server -n $ans -o name 2>$null)) {
    Invoke-Checked -What 'argocd 설치' -Script {
        kubectl apply --server-side --force-conflicts -n $ans -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    }
    Invoke-Checked -What 'argocd 준비 대기' -Script { kubectl rollout status deploy/argocd-server -n $ans --timeout=420s }
}
$projYaml = Get-Content "$PSScriptRoot\config\argocd\project.yaml" -Raw -Encoding UTF8
$projYaml = $projYaml.Replace('REPO_URL_PLACEHOLDER', $cfg.argocd.repoUrl)
$projTmp = Join-Path $env:TEMP 'argocd-project-prd.yaml'
$projYaml | Out-File $projTmp -Encoding utf8
Invoke-Checked -What 'AppProject 적용' -Script { kubectl apply -f $projTmp }

$appYaml = Get-Content "$PSScriptRoot\config\argocd\application.yaml" -Raw -Encoding UTF8
$appYaml = $appYaml.Replace('REPO_URL_PLACEHOLDER', $cfg.argocd.repoUrl)
$appYaml = $appYaml.Replace('TARGET_REVISION_PLACEHOLDER', $cfg.argocd.targetRevision)
$tmp = Join-Path $env:TEMP 'argocd-app-prd.yaml'
$appYaml | Out-File $tmp -Encoding utf8
Invoke-Checked -What 'Application 적용' -Script { kubectl apply -f $tmp }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Step "4/4 동기화 — 사람이 승인한 뒤에만 반영"
$hasRemote = $false
Push-Location $RepoRoot; try { $hasRemote = [bool](git remote) } finally { Pop-Location }

if ($hasRemote) {
    Write-Info 'Argo CD 에 수동 Sync 를 요청합니다(운영 정책: 자동 동기화 금지).'
    kubectl patch application $cfg.argocd.appName -n $ans --type merge `
      -p '{"operation":{"sync":{"prune":false,"syncStrategy":{"apply":{"force":false}}}}}' 2>$null
} else {
    Write-Warn2 'Git 원격이 없어 Argo CD 경로를 쓸 수 없습니다 — kubectl 로 직접 적용합니다.'
    Invoke-Checked -What 'kustomize 적용' -Script { kubectl apply -k "$PSScriptRoot\config\k8s\overlays\prd" }
}

Wait-Condition -What 'Argo CD 동기화로 네임스페이스 생성' -TimeoutSec 180 -IntervalSec 10 -Condition {
    kubectl get namespace $($cfg.app.namespace) -o name 2>$null
}
Invoke-Checked -What '롤아웃 대기(무중단)' -Script {
    kubectl rollout status deploy/$($cfg.app.name) -n $($cfg.app.namespace) --timeout=600s
}

Write-Step "외부 접속 주소 확인 (관리형 NGINX Ingress)"
$ns = $cfg.app.namespace
$ip = $null
Wait-Condition -What 'Ingress 주소 할당' -TimeoutSec 420 -IntervalSec 15 -Condition {
    $script:ip = kubectl get ingress $($cfg.app.name) -n $ns -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    return [bool]$script:ip
}
$base = "http://$ip"
$cfgObj = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cfgObj.test.baseUrl = $base
$cfgObj | ConvertTo-Json -Depth 10 | Out-File $ConfigPath -Encoding utf8
Write-Ok ("운영 접속 주소: " + $base)
Wait-Condition -What '앱 헬스 응답' -TimeoutSec 300 -IntervalSec 10 -Condition { Test-HttpOk -Url ($base + '/healthz') }
Write-Ok "prd 배포 완료 — 다음: .\50_test_unit.ps1"
