<#  prd 전제조건 점검 — 구독·권한·공급자·이름 규칙·승격 원본 확인
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\10_prereq.ps1 [-Force]
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

Write-Step "prd 전제조건 점검"
$results = @()
function Add-Check { param($n,$ok,$d) $script:results += [ordered]@{ Name=$n; Status=$(if($ok){'Pass'}else{'Fail'}); Detail=$d } }

foreach ($t in @('az','kubectl','git','node')) {
    $ok = Test-CommandExists $t
    if ($ok) { Write-Ok ("{0} 확인" -f $t) } else { Write-Err2 ("{0} 없음" -f $t) }
    Add-Check ("명령: " + $t) $ok ''
}

$acct = $null
try { $acct = az account show -o json 2>$null | ConvertFrom-Json } catch { }
Add-Check 'Azure 로그인' ($null -ne $acct) $(if($acct){$acct.name}else{'미로그인'})
if ($acct) { Write-Ok ("구독: " + $acct.name) }

# 운영은 공급자가 더 많이 필요하다
if ($acct) {
    foreach ($ns in @('Microsoft.ContainerService','Microsoft.ContainerRegistry','Microsoft.DBforPostgreSQL',
                      'Microsoft.Cache','Microsoft.KeyVault','Microsoft.Storage','Microsoft.OperationalInsights',
                      'Microsoft.Insights','Microsoft.Network','Microsoft.Monitor')) {
        $state = az provider show -n $ns --query registrationState -o tsv 2>$null
        $ok = ($state -eq 'Registered')
        if (-not $ok) { Write-Warn2 ("{0} 미등록 — az provider register --namespace {0} --wait" -f $ns) }
        Add-Check ("공급자: " + $ns) $ok $state
    }
}

# 전역 고유 이름 형식
Add-Check 'ACR 이름 형식' ($cfg.azure.acrName -cmatch '^[a-z0-9]{5,50}$') $cfg.azure.acrName
Add-Check 'PostgreSQL 이름 형식' ($cfg.azure.data.postgres.name -cmatch '^[a-z0-9-]{3,63}$') $cfg.azure.data.postgres.name

# 관리자 비밀번호 환경 변수 (값은 출력하지 않는다)
$pwSet = [bool][Environment]::GetEnvironmentVariable($cfg.azure.data.postgres.adminPasswordEnvVar)
if (-not $pwSet) { Write-Err2 ("환경 변수 {0} 를 먼저 설정하세요 (12자 이상·3종 조합)." -f $cfg.azure.data.postgres.adminPasswordEnvVar) }
Add-Check ('DB 관리자 비밀번호 환경 변수: ' + $cfg.azure.data.postgres.adminPasswordEnvVar) $pwSet '값은 출력하지 않음'

# GitOps 저장소
$repoOk = ($cfg.argocd.repoUrl -notmatch '<')
Add-Check 'Argo CD 저장소 지정' $repoOk $cfg.argocd.repoUrl

# 승격 원본(stg 검증 결과)이 있는가 — 운영은 검증되지 않은 것을 올리지 않는다
$stgVerify = Get-ChildItem "$PSScriptRoot\..\stg\reports" -Filter 'stg_verify_*.json' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
$stgOk = $false
if ($stgVerify) { $j = Get-Content $stgVerify.FullName -Raw | ConvertFrom-Json; $stgOk = ($j.fail -eq 0) }
if (-not $stgOk) { Write-Warn2 'stg 검증 통과 기록이 없습니다. 운영 배포는 stg 검증 후에 진행하세요.' }
Add-Check 'stg 검증 통과 기록 존재' $stgOk $(if($stgVerify){$stgVerify.Name}else{'없음'})

$ok = New-TestReport -Env 'prd' -Kind 'prereq' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { Write-Err2 '전제조건 미충족 — 운영 배포를 중단합니다.'; exit 1 }
Write-Ok 'prd 전제조건 충족 — 다음: .\20_config.ps1'
