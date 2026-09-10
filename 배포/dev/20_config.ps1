<#  dev 환경 구성 — k3d 클러스터·네임스페이스·설정/비밀 생성
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\20_config.ps1 [-Force]
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.dev.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath

Write-Step "k3d 클러스터 구성"

$clusterName = $cfg.cluster.name
$exists = (k3d cluster list -o json | ConvertFrom-Json) | Where-Object { $_.name -eq $clusterName }

if ($exists) {
    Write-Info ("클러스터 '{0}' 가 이미 있습니다 — 재사용합니다." -f $clusterName)
} else {
    Write-Info ("클러스터 '{0}' 생성 (호스트 {1} → NodePort {2})" -f $clusterName, $cfg.cluster.hostPort, $cfg.cluster.nodePort)
    Invoke-Checked -What 'k3d cluster create' -Script {
        k3d cluster create $clusterName `
            --agents $cfg.cluster.agents `
            --image  $cfg.cluster.k3sImage `
            --port ("{0}:{1}@loadbalancer" -f $cfg.cluster.hostPort, $cfg.cluster.nodePort) `
            --wait
    }
}
Invoke-Checked -What 'kubectl 컨텍스트 전환' -Script { kubectl config use-context ("k3d-" + $clusterName) }

# 일부 Windows/Docker Desktop 조합에서 host.docker.internal 이 호스트에서 라우팅되지 않아
# kubectl 이 API 서버에 연결하지 못하는 경우가 있다 — 같은 포트의 127.0.0.1 로 바꿔 접속성을 보정한다.
$jsonpathExpr = "{.clusters[?(@.name=='k3d-$clusterName')].cluster.server}"
$ctxServer = & kubectl config view --raw -o "jsonpath=$jsonpathExpr" 2>$null
if ($ctxServer -match '^https://host\.docker\.internal:(\d+)$') {
    $apiPort = $Matches[1]
    # 주의: --server=(...) 처럼 "플래그=(식)"을 나눠 쓰면 네이티브 인자 전달 중 토큰이 쪼개질 수 있다
    # (예: "kubeconfigName --server=url" → "kubeconfigName" + "url" 두 개로 분리). 한 문자열로 보간한다.
    $serverArg = "--server=https://127.0.0.1:$apiPort"
    kubectl config set-cluster "k3d-$clusterName" $serverArg | Out-Null
    Write-Info ("kubeconfig 서버 주소를 127.0.0.1:{0} 로 보정했습니다(host.docker.internal 라우팅 이슈 우회)" -f $apiPort)
}

Write-Step "네임스페이스 · 설정(ConfigMap) · 비밀(Secret) 생성"
$ns = $cfg.app.namespace
Invoke-Checked -What 'namespace 적용' -Script { kubectl apply -f "$PSScriptRoot\config\k8s\namespace.yaml" }

# myapp은 better-sqlite3(파일 기반 임베디드 DB)를 사용해 별도 DB 서버가 필요 없다.
# 비밀값(GitHub PAT, Notion 토큰)은 반드시 환경 변수에서 읽는다 — 스크립트/설정 파일에 평문으로 두지 않는다.
# 값이 없어도(로컬 실습) 앱은 낮은 Rate Limit/업로드 비활성 상태로 정상 동작하므로 기본값을 만들지 않는다.
$githubToken  = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN')
$notionToken  = [Environment]::GetEnvironmentVariable('NOTION_TOKEN')
$notionPageId = [Environment]::GetEnvironmentVariable('NOTION_PARENT_PAGE_ID')
if (-not $githubToken)  { Write-Warn2 '환경 변수 GITHUB_TOKEN 이 없습니다 — 비인증 상태(60회/시간)로 배포됩니다.' }
if (-not $notionToken)  { Write-Warn2 '환경 변수 NOTION_TOKEN 이 없습니다 — Notion 업로드가 401로 응답합니다(정상 동작 범위).' }
if (-not $notionPageId) { Write-Warn2 '환경 변수 NOTION_PARENT_PAGE_ID 가 없습니다.' }

# ConfigMap — 비밀이 아닌 설정
Invoke-Checked -What 'ConfigMap 적용' -Script {
    kubectl create configmap myapp-config -n $ns `
        --from-literal=APP_ENV=dev `
        --from-literal=PORT=8080 `
        --dry-run=client -o yaml | kubectl apply -f -
}
# Secret — 비밀값(값이 없으면 빈 문자열로 생성 — 앱이 "미설정"으로 정상 처리한다)
Invoke-Checked -What 'Secret 적용' -Script {
    kubectl create secret generic myapp-secret -n $ns `
        --from-literal=GITHUB_TOKEN=$githubToken `
        --from-literal=NOTION_TOKEN=$notionToken `
        --from-literal=NOTION_PARENT_PAGE_ID=$notionPageId `
        --dry-run=client -o yaml | kubectl apply -f -
}

Write-Info 'myapp은 SQLite(better-sqlite3)를 컨테이너 내부에 저장하므로 postgres.yaml은 적용하지 않는다.'
Write-Info '(postgres.yaml 파일 자체는 다른 3차시 앱과의 구조 비교용으로 남겨둔다 — 실습산출물/3차시/06_배포스크립트_조정.md 참고)'

Write-Ok "dev 환경 구성 완료 — 다음: .\30_build.ps1"
