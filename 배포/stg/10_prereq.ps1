<#  stg 전제조건 점검 — Azure CLI·로그인·구독·도구·Git 확인
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\10_prereq.ps1 [-Force]
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

Write-Step "stg 전제조건 점검"
$results = @()
function Add-Check { param($n, $ok, $d) $script:results += [ordered]@{ Name=$n; Status=$(if($ok){'Pass'}else{'Fail'}); Detail=$d } }

foreach ($t in @(
    @{n='az';      h='1차시 4-2 Azure CLI 설치'},
    @{n='kubectl'; h='az aks install-cli'},
    @{n='kustomize';h='kubectl 내장 kustomize(-k) 사용 가능하면 선택'},
    @{n='git';     h='1차시 1-2 Git for Windows 설치'},
    @{n='docker';  h='로컬 빌드 대신 az acr build 를 쓰면 선택'},
    @{n='node';    h='테스트 실행용'}
)) {
    $ok = Test-CommandExists $t.n
    $required = $t.n -in @('az','kubectl','git','node')
    if ($ok) { Write-Ok ("{0} 확인" -f $t.n) }
    elseif ($required) { Write-Err2 ("{0} 없음 — {1}" -f $t.n, $t.h) }
    else { Write-Warn2 ("{0} 없음(선택) — {1}" -f $t.n, $t.h) }
    if ($required) { Add-Check ("명령: " + $t.n) $ok $t.h }
}

# Azure 로그인·구독
$acct = $null
try { $acct = az account show -o json 2>$null | ConvertFrom-Json } catch { }
if ($acct) { Write-Ok ("Azure 로그인: " + $acct.name) } else { Write-Err2 "az login 을 먼저 실행하세요." }
Add-Check 'Azure 로그인 상태' ($null -ne $acct) $(if($acct){$acct.name}else{'미로그인'})

# 리전 가용성
$loc = $cfg.azure.location
$locOk = $false
if ($acct) { $locOk = [bool](az account list-locations --query "[?name=='$loc'].name" -o tsv) }
Add-Check ("리전 사용 가능: " + $loc) $locOk $loc

# 리소스 공급자
if ($acct) {
    foreach ($ns in @('Microsoft.ContainerService','Microsoft.ContainerRegistry','Microsoft.Network')) {
        $state = az provider show -n $ns --query registrationState -o tsv 2>$null
        $ok = ($state -eq 'Registered')
        if (-not $ok) { Write-Warn2 ("{0} 미등록 — az provider register --namespace {0} --wait" -f $ns) }
        Add-Check ("공급자 등록: " + $ns) $ok $state
    }
}

# ACR 이름 규칙(소문자·숫자·5~50자·전역 고유)
$acr = $cfg.azure.acrName
$acrFormatOk = ($acr -cmatch '^[a-z0-9]{5,50}$')
Add-Check 'ACR 이름 형식(소문자·숫자 5~50)' $acrFormatOk $acr

# GitOps 저장소 설정 여부
$repoOk = ($cfg.argocd.repoUrl -notmatch '<' )
if (-not $repoOk) { Write-Err2 "config/env.stg.json 의 argocd.repoUrl 을 실제 Git 저장소 URL 로 바꾸세요." }
Add-Check 'Argo CD 대상 Git 저장소 지정' $repoOk $cfg.argocd.repoUrl

# 현재 폴더가 Git 저장소인가 (GitOps 는 Git 이 진실의 원천)
$inGit = $false
try { git -C $RepoRoot rev-parse --is-inside-work-tree 1>$null 2>$null; $inGit = ($LASTEXITCODE -eq 0) } catch { }
if (-not $inGit) { Write-Warn2 "현재 폴더가 Git 저장소가 아닙니다 — git init 후 원격 저장소에 push 해야 GitOps 가 동작합니다." }
Add-Check 'Git 저장소 초기화' $inGit $RepoRoot

$ok = New-TestReport -Env 'stg' -Kind 'prereq' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { Write-Err2 '전제조건 미충족 — 위 [FAIL] 항목을 먼저 해결하세요.'; exit 1 }
Write-Ok 'stg 전제조건 모두 충족 — 다음: .\20_config.ps1'
