<#  stg 구성 — 리소스 그룹·ACR·AKS 생성 후 Argo CD 설치·구성
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\20_config.ps1 [-Force]
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

Write-Step "Azure 인프라 구성 (리소스 그룹 · ACR · AKS)"
$loc = $cfg.azure.location
$acr = $cfg.azure.acrName
$aks = $cfg.azure.aks.name

Write-Warn2 "AKS·ACR 은 시간당 과금됩니다. 실습 후 .\90_cleanup.ps1 로 반드시 정리하세요."

# 1) 리소스 그룹
Invoke-Checked -What 'resource group' -Script { az group create -n $RG -l $loc -o none }

# 2) ACR (이름은 전역 고유)
$acrExists = az acr show -n $acr -g $RG -o none 2>$null; $acrExists = ($LASTEXITCODE -eq 0)
if (-not $acrExists) {
    $avail = az acr check-name -n $acr --query nameAvailable -o tsv
    if ($avail -ne 'true') { throw ("ACR 이름 '{0}' 을 사용할 수 없습니다. env.stg.json 의 acrName 을 바꾸세요." -f $acr) }
    Invoke-Checked -What 'acr create' -Script { az acr create -g $RG -n $acr --sku Basic -l $loc -o none }
} else { Write-Info ("ACR '{0}' 재사용" -f $acr) }

# 3) AKS
$aksExists = az aks show -g $RG -n $aks -o none 2>$null; $aksExists = ($LASTEXITCODE -eq 0)
if (-not $aksExists) {
    Write-Info "AKS 생성에는 5~10분이 걸립니다."
    $argsList = @(
        'aks','create','-g',$RG,'-n',$aks,'-l',$loc,
        '--node-count', $cfg.azure.aks.nodeCount,
        '--node-vm-size', $cfg.azure.aks.nodeSize,
        '--network-plugin', $cfg.azure.aks.networkPlugin,
        '--network-plugin-mode', $cfg.azure.aks.networkPluginMode,
        '--tier', $cfg.azure.aks.tier,
        '--attach-acr', $acr,
        '--generate-ssh-keys','--only-show-errors','-o','none'
    )
    if ($cfg.azure.aks.enableOidcIssuer)        { $argsList += '--enable-oidc-issuer' }
    if ($cfg.azure.aks.enableWorkloadIdentity)  { $argsList += '--enable-workload-identity' }
    if ($cfg.azure.aks.kubernetesVersion)       { $argsList += @('--kubernetes-version', $cfg.azure.aks.kubernetesVersion) }
    Invoke-Checked -What 'aks create' -Script { az @argsList }
} else {
    Write-Info ("AKS '{0}' 재사용" -f $aks)
    Invoke-Checked -What 'acr 연결 확인' -Script { az aks update -g $RG -n $aks --attach-acr $acr -o none }
}

Invoke-Checked -What 'kubeconfig 병합' -Script { az aks get-credentials -g $RG -n $aks --overwrite-existing }

Write-Step "Argo CD 설치"
$ans = $cfg.argocd.namespace
kubectl create namespace $ans --dry-run=client -o yaml | kubectl apply -f -
$installed = kubectl get deploy argocd-server -n $ans -o name 2>$null
if (-not $installed) {
    Invoke-Checked -What 'argocd 매니페스트 적용' -Script {
        # --server-side 필수: Argo CD 의 CRD 는 client-side apply 가 쓰는
        # last-applied-configuration 주석의 262144바이트 한도를 넘는다.
        kubectl apply -n $ans --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    }
} else { Write-Info 'Argo CD 가 이미 설치되어 있습니다 — 재사용' }

Invoke-Checked -What 'argocd-server 준비 대기' -Script { kubectl rollout status deploy/argocd-server -n $ans --timeout=420s }
Invoke-Checked -What 'argocd-repo-server 준비 대기' -Script { kubectl rollout status deploy/argocd-repo-server -n $ans --timeout=300s }

Write-Step "Argo CD Project · Application 등록"
Invoke-Checked -What 'AppProject 적용' -Script { kubectl apply -f "$PSScriptRoot\config\argocd\project.yaml" }

# Application 의 repoURL 을 설정값으로 치환해 적용
$appYaml = Get-Content "$PSScriptRoot\config\argocd\application.yaml" -Raw -Encoding UTF8
$appYaml = $appYaml.Replace('REPO_URL_PLACEHOLDER', $cfg.argocd.repoUrl)
$appYaml = $appYaml -replace 'targetRevision: .*', ("targetRevision: " + $cfg.argocd.targetRevision)
$appYaml = $appYaml -replace 'path: .*', ("path: " + $cfg.argocd.path)
$tmp = Join-Path $env:TEMP 'argocd-app-stg.yaml'
$appYaml | Out-File $tmp -Encoding utf8
Invoke-Checked -What 'Application 적용' -Script { kubectl apply -f $tmp }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Step "앱 네임스페이스 · 비밀 생성 (Secret 은 Git 에 두지 않는다)"
$ns = $cfg.app.namespace
kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
$dbPw = [Environment]::GetEnvironmentVariable($cfg.db.passwordEnvVar)
if (-not $dbPw) {
    Write-Warn2 ("환경 변수 {0} 가 없어 임의 값을 생성합니다. 값은 화면에 출력하지 않습니다." -f $cfg.db.passwordEnvVar)
    $bytes = New-Object 'System.Byte[]' 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $dbPw = [Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', 'x'
}
kubectl create secret generic myapp-secret -n $ns --from-literal=DB_PASSWORD=$dbPw --dry-run=client -o yaml | kubectl apply -f -
Write-Ok 'Secret 적용 완료 (값은 출력하지 않음)'

Write-Host ""
Write-Info "Argo CD 초기 admin 비밀번호 확인 방법:"
Write-Host '  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d' -ForegroundColor Gray
Write-Info ("Argo CD UI 접속:  kubectl port-forward svc/argocd-server -n {0} {1}:443  →  https://localhost:{1}" -f $ans, $cfg.argocd.localPortForward)
Write-Ok "stg 구성 완료 — 다음: .\30_build.ps1"
