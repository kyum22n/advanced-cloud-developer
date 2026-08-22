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

Write-Step "네임스페이스 · 설정(ConfigMap) · 비밀(Secret) 생성"
$ns = $cfg.app.namespace
Invoke-Checked -What 'namespace 적용' -Script { kubectl apply -f "$PSScriptRoot\config\k8s\namespace.yaml" }

# 비밀번호는 환경 변수에서 읽는다 — 스크립트/설정 파일에 평문으로 두지 않는다
$pwEnv = $cfg.db.passwordEnvVar
$dbPw  = [Environment]::GetEnvironmentVariable($pwEnv)
if (-not $dbPw) {
    Write-Warn2 ("환경 변수 {0} 가 없어 개발용 기본값을 사용합니다. 운영에서는 절대 이렇게 하지 마세요." -f $pwEnv)
    $dbPw = $cfg.db.passwordDefault
}

# ConfigMap — 비밀이 아닌 설정
Invoke-Checked -What 'ConfigMap 적용' -Script {
    kubectl create configmap myapp-config -n $ns `
        --from-literal=APP_ENV=dev `
        --from-literal=PORT=8080 `
        --from-literal=DB_HOST=postgres `
        --from-literal=DB_PORT=5432 `
        --from-literal=DB_NAME=$($cfg.db.name) `
        --from-literal=DB_USER=$($cfg.db.user) `
        --from-literal=DB_SSL=false `
        --dry-run=client -o yaml | kubectl apply -f -
}
# Secret — 비밀값
Invoke-Checked -What 'Secret 적용' -Script {
    kubectl create secret generic myapp-secret -n $ns `
        --from-literal=DB_PASSWORD=$dbPw `
        --dry-run=client -o yaml | kubectl apply -f -
}

Write-Step "개발용 PostgreSQL 배포 (in-cluster)"
Invoke-Checked -What 'postgres 적용' -Script { kubectl apply -f "$PSScriptRoot\config\k8s\postgres.yaml" }
Invoke-Checked -What 'postgres 준비 대기' -Script { kubectl rollout status deploy/postgres -n $ns --timeout=180s }

Write-Ok "dev 환경 구성 완료 — 다음: .\30_build.ps1"
