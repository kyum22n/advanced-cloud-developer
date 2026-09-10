<#  prd 검증 — 가용성·보안·관측·복구 기준 종합 점검
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\80_verify.ps1 [-Force]
    ⚠️ 운영 환경 스크립트입니다. 파괴적 작업은 반드시 확인을 거칩니다.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.prd.json",
    [string]$AppPath,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
. "$PSScriptRoot\..\common\identity.ps1"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$cfg = Get-DeployConfig -Path $ConfigPath
$RG  = $cfg.azure.resourceGroup

Write-Step "운영 배포 검증 (Production Readiness)"
$ns = $cfg.app.namespace
$base = $cfg.test.baseUrl
$results = @()
function Add-V { param($n,$ok,$d) $script:results += [ordered]@{ Name=$n; Status=$(if($ok){'Pass'}else{'Fail'}); Detail=$d } }

# ── 가용성 ──────────────────────────────────────────────
$dep = kubectl get deploy $cfg.app.name -n $ns -o json 2>$null | ConvertFrom-Json
Add-V ("replicas >= " + $cfg.app.replicas) ($dep -and $dep.status.readyReplicas -ge $cfg.app.replicas) ("ready=" + $(if($dep){$dep.status.readyReplicas}else{'n/a'}))

$pods = kubectl get pods -n $ns -l app=$($cfg.app.name) -o json 2>$null | ConvertFrom-Json
$zones = @()
if ($pods) {
    foreach ($p in $pods.items) {
        $node = $p.spec.nodeName
        $z = kubectl get node $node -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>$null
        if ($z) { $zones += $z }
    }
}
$uniqZones = ($zones | Select-Object -Unique).Count
Add-V '파드가 2개 이상 가용성 영역에 분산' ($uniqZones -ge 2) ("zones=" + (($zones | Select-Object -Unique) -join ','))

$pdb = kubectl get pdb $cfg.app.name -n $ns -o json 2>$null | ConvertFrom-Json
Add-V 'PodDisruptionBudget 존재' ($null -ne $pdb) ("minAvailable=" + $(if($pdb){$pdb.spec.minAvailable}else{'없음'}))

$hpa = kubectl get hpa $cfg.app.name -n $ns -o json 2>$null | ConvertFrom-Json
Add-V 'HPA 구성' ($null -ne $hpa) ("min=" + $(if($hpa){$hpa.spec.minReplicas}else{'-'}) + " max=" + $(if($hpa){$hpa.spec.maxReplicas}else{'-'}))

# ── 보안 ────────────────────────────────────────────────
$sa = kubectl get sa $cfg.app.serviceAccount -n $ns -o json 2>$null | ConvertFrom-Json
$wi = $sa -and $sa.metadata.annotations.'azure.workload.identity/client-id' -and
      $sa.metadata.annotations.'azure.workload.identity/client-id' -notmatch 'PLACEHOLDER'
Add-V '워크로드 ID(ServiceAccount 주석) 구성' $wi '비밀번호 없는 Azure 접근'

$img = kubectl get deploy $cfg.app.name -n $ns -o jsonpath='{.spec.template.spec.containers[0].image}' 2>$null
Add-V '불변 이미지 태그 사용(latest 금지)' ($img -notmatch ':latest$') ("image=" + $img)

$sc = kubectl get deploy $cfg.app.name -n $ns -o json 2>$null | ConvertFrom-Json
$roFs = $sc.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem
$nonRoot = $sc.spec.template.spec.securityContext.runAsNonRoot
Add-V '비루트 실행 + 읽기 전용 루트 파일시스템' (($nonRoot -eq $true) -and ($roFs -eq $true)) ("runAsNonRoot=$nonRoot readOnlyRootFs=$roFs")

# PaaS DB 공용 접근 차단 확인
$pgPublic = az postgres flexible-server show -g $RG -n $cfg.azure.data.postgres.name --query network.publicNetworkAccess -o tsv 2>$null
Add-V 'PostgreSQL 공용 네트워크 액세스 차단' ($pgPublic -eq 'Disabled') ("publicNetworkAccess=" + $pgPublic)

$pgHa = az postgres flexible-server show -g $RG -n $cfg.azure.data.postgres.name --query highAvailability.mode -o tsv 2>$null
Add-V 'PostgreSQL 고가용성 구성' ($pgHa -and $pgHa -ne 'Disabled') ("haMode=" + $pgHa)

$pgBackup = az postgres flexible-server show -g $RG -n $cfg.azure.data.postgres.name --query backup.backupRetentionDays -o tsv 2>$null
Add-V 'PostgreSQL 백업 보존 >= 7일' ([int]($pgBackup -as [int]) -ge 7) ("retention=" + $pgBackup + "일")

# ── 아이덴티티 (Managed Identity / Workload Identity) ───
# '적용했다'가 아니라 '작동한다'를 확인한다 — 리소스와 클러스터 양쪽을 실제 조회
$state = $null
$statePath = "$PSScriptRoot\reports\infra-state.json"
if (Test-Path $statePath) { $state = Get-Content $statePath -Raw | ConvertFrom-Json }
$idName = $cfg.identity.userAssignedName
if (-not $idName) { $idName = $cfg.app.workloadIdentityName }
$idResults = Test-IdentityPosture -ResourceGroup $RG -AksName $cfg.azure.aks.name `
    -IdentityName $idName -Namespace $ns -ServiceAccount $cfg.app.serviceAccount `
    -KeyVaultName $(if ($state) { $state.keyvaultName } else { $null }) `
    -PostgresName $cfg.azure.data.postgres.name `
    -StorageAccount $(if ($state) { $state.storageAccount } else { $null }) `
    -RedisName $cfg.azure.data.redis.name `
    -AcrName $cfg.azure.acrName
foreach ($x in $idResults) { $results += $x }

# ── 관측 ────────────────────────────────────────────────
$addons = az aks show -g $RG -n $cfg.azure.aks.name --query addonProfiles -o json 2>$null | ConvertFrom-Json
$mon = $addons.omsagent.enabled -or $addons.omsAgent.enabled
Add-V 'Container Insights 사용' ([bool]$mon) '로그·컨테이너 지표 수집'

# ── 엔드포인트 ──────────────────────────────────────────
if ($base) { foreach ($ep in @('/healthz','/readyz','/version')) { Add-V ("엔드포인트 " + $ep) (Test-HttpOk -Url ($base + $ep)) ($base + $ep) } }

# ── 앱 수준 아이덴티티 (/version 응답으로 "적용했다"가 아니라 "작동한다"를 다시 한번 확인) ──
if ($base) {
    $verRaw = $null
    try { $verRaw = Invoke-WebRequest -Uri ($base + '/version') -UseBasicParsing -TimeoutSec 10 } catch { }
    if ($verRaw) {
        $verBody = $verRaw.Content
        $verJson = $null
        try { $verJson = $verBody | ConvertFrom-Json } catch { }

        # 앱 스스로도 워크로드 ID를 인지하고 있는가(클러스터 측 뿐 아니라 프로세스 안에서도)
        Add-V '/version: 앱이 워크로드 ID를 인지함' ($verJson -and $verJson.identity.workloadIdentity -eq $true) `
            ("workloadIdentity=" + $(if($verJson){$verJson.identity.workloadIdentity}else{'응답 없음'}))

        # GITHUB_TOKEN/NOTION_TOKEN이 env 또는 keyvault 중 하나로는 조달되고 있는가(둘 다 unset이면 설정 누락)
        $srcOk = $verJson -and $verJson.identity.sources.GITHUB_TOKEN -ne 'unset' -and $verJson.identity.sources.NOTION_TOKEN -ne 'unset'
        Add-V '/version: 비밀 출처(env|keyvault)가 확인됨' $srcOk `
            ("sources=" + $(if($verJson){$verJson.identity.sources | ConvertTo-Json -Compress}else{'응답 없음'}))

        # 응답 본문 어디에도 토큰류 문자열이 그대로 실려 있지 않아야 한다(값 유출 방지의 최종 방어선)
        $leaked = $verBody -match 'ghp_[A-Za-z0-9]{10,}|github_pat_[A-Za-z0-9_]{10,}|ntn_[A-Za-z0-9]{10,}|secret_[A-Za-z0-9]{10,}'
        Add-V '/version 응답에 자격 증명 값이 없음' (-not $leaked) 'ghp_/ntn_/secret_ 패턴 미검출'
    } else {
        Add-V '/version: 앱이 워크로드 ID를 인지함' $false '응답 없음(엔드포인트 점검 항목 참고)'
        Add-V '/version: 비밀 출처(env|keyvault)가 확인됨' $false '응답 없음'
        Add-V '/version 응답에 자격 증명 값이 없음' $false '응답 없음'
    }
}

# ── 롤백 가능성 ─────────────────────────────────────────
$hist = kubectl rollout history deploy/$($cfg.app.name) -n $ns 2>$null
Add-V '롤백 가능(리비전 이력 2개 이상)' (($hist -split "`n" | Where-Object { $_ -match '^\d' }).Count -ge 2) '이전 리비전으로 즉시 복귀 가능'

$ok = New-TestReport -Env 'prd' -Kind 'verify' -Results $results -OutDir "$PSScriptRoot\reports"
Write-Host ""
kubectl get deploy,hpa,pdb,ingress -n $ns
Write-IdentitySummary -Results $idResults
if (-not $ok) { Write-Err2 '운영 준비 기준 미충족 항목이 있습니다 — 위 [FAIL] 을 확인하세요.'; exit 1 }
Write-Ok 'prd 운영 준비 검증 통과'
