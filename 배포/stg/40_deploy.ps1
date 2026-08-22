<#  stg 배포 — GitOps: overlay 이미지 태그를 Git 에 커밋 → Argo CD 동기화
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\40_deploy.ps1 [-Force]
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

Write-Step "GitOps 배포 — Git 이 '무엇을 배포할지'의 단일 진실"

$buildFile = "$PSScriptRoot\reports\last-build.json"
if (-not (Test-Path $buildFile)) { Write-Err2 '빌드 기록이 없습니다. 먼저 .\30_build.ps1 을 실행하세요.'; exit 1 }
$b = Get-Content $buildFile -Raw | ConvertFrom-Json

$kustPath = "$PSScriptRoot\config\k8s\overlays\stg\kustomization.yaml"
$k = Get-Content $kustPath -Raw -Encoding UTF8

# ① overlay 의 이미지 이름·태그를 이번 빌드로 교체
$k = $k -replace 'newName: .*', ("newName: {0}/{1}" -f $b.registry, $b.repository)
$k = $k -replace 'newTag: .*',  ("newTag: " + $b.tag)
$k | Out-File $kustPath -Encoding utf8 -NoNewline
Write-Ok ("overlay 이미지 태그 갱신: " + $b.tag)

# ② Git 커밋·푸시 — 이 커밋이 곧 '배포 지시'
Push-Location $RepoRoot
try {
    $inGit = $false
    git rev-parse --is-inside-work-tree 1>$null 2>$null; $inGit = ($LASTEXITCODE -eq 0)
    if ($inGit) {
        git add -- "배포/stg/config/k8s/overlays/stg/kustomization.yaml" 2>$null
        $changed = (git diff --cached --name-only)
        if ($changed) {
            Invoke-Checked -What 'git commit' -Script { git commit -m ("deploy(stg): image tag {0}" -f $b.tag) --no-verify }
            $hasRemote = (git remote) -ne $null
            if ($hasRemote) { Invoke-Checked -What 'git push' -Script { git push } }
            else { Write-Warn2 '원격 저장소(remote)가 없어 push 를 건너뜁니다 — Argo CD 가 변경을 볼 수 없습니다.' }
        } else { Write-Info '변경 사항이 없어 커밋을 건너뜁니다(같은 태그).' }
    } else {
        Write-Warn2 'Git 저장소가 아니어서 커밋을 건너뜁니다. 아래 kubectl 직접 적용으로 대체합니다.'
    }
} finally { Pop-Location }

# ③ Argo CD 동기화
Write-Step "Argo CD 동기화"
$ans = $cfg.argocd.namespace
$appName = $cfg.argocd.appName
$hasApp = kubectl get application $appName -n $ans -o name 2>$null

if ($hasApp) {
    Invoke-Checked -What 'refresh 요청' -Script {
        kubectl patch application $appName -n $ans --type merge `
          -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
    }
    Write-Info 'syncPolicy=automated 이므로 Argo CD 가 자동으로 동기화합니다.'
    Wait-Condition -What 'Argo CD Synced & Healthy' -TimeoutSec 420 -IntervalSec 10 -Condition {
        $j = kubectl get application $appName -n $ans -o json 2>$null | ConvertFrom-Json
        return ($j.status.sync.status -eq 'Synced' -and $j.status.health.status -eq 'Healthy')
    }
} else {
    Write-Warn2 'Argo CD Application 이 없어 kubectl 로 직접 적용합니다(비 GitOps 경로).'
    Invoke-Checked -What 'kustomize 적용' -Script { kubectl apply -k "$PSScriptRoot\config\k8s\overlays\stg" }
    Invoke-Checked -What '롤아웃 대기' -Script { kubectl rollout status deploy/$($cfg.app.name) -n $($cfg.app.namespace) --timeout=300s }
}

Write-Step "외부 접속 주소 확인 (LoadBalancer)"
$ns = $cfg.app.namespace
$ip = $null
Wait-Condition -What 'LoadBalancer 외부 IP 할당' -TimeoutSec 300 -IntervalSec 10 -Condition {
    $script:ip = kubectl get svc $($cfg.app.name) -n $ns -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    return [bool]$script:ip
}
$base = "http://$ip"
Write-Ok ("접속 주소: " + $base)

# 테스트 스크립트가 쓰도록 설정 파일에 기록
$cfgObj = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cfgObj.test.baseUrl = $base
$cfgObj | ConvertTo-Json -Depth 8 | Out-File $ConfigPath -Encoding utf8

Wait-Condition -What '앱 헬스 응답' -TimeoutSec 180 -IntervalSec 5 -Condition { Test-HttpOk -Url ($base + '/healthz') }
Write-Ok "stg 배포 완료 — 다음: .\50_test_unit.ps1"
