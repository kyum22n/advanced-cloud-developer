<#  dev 전제조건 점검 — 도구·엔진·포트 확인
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\10_prereq.ps1 [-Force]
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

Write-Step "dev 전제조건 점검"
$results = @()

function Add-Check { param($Name, $Ok, $Detail)
    $script:results += [ordered]@{ Name = $Name; Status = $(if ($Ok) { 'Pass' } else { 'Fail' }); Detail = $Detail } }

# 1) 필수 명령
foreach ($t in @(
    @{n='docker'; h='1차시 1-5 Docker Desktop 설치'},
    @{n='kubectl'; h='k3d 설치 시 함께 설치되거나 winget install Kubernetes.kubectl'},
    @{n='k3d';     h='winget install k3d  또는  choco install k3d'},
    @{n='node';    h='1차시 1-4 Node.js LTS 설치'}
)) {
    $ok = Test-CommandExists $t.n
    if ($ok) { Write-Ok ("{0} 확인" -f $t.n) } else { Write-Err2 ("{0} 없음 — {1}" -f $t.n, $t.h) }
    Add-Check ("명령: " + $t.n) $ok $t.h
}

# 2) Docker 엔진 기동 여부
$engine = $false
try { docker info 1>$null 2>$null; $engine = ($LASTEXITCODE -eq 0) } catch { $engine = $false }
if ($engine) { Write-Ok 'Docker 엔진 기동 중' } else { Write-Err2 'Docker Desktop 을 실행하세요' }
Add-Check 'Docker 엔진 기동' $engine 'docker info'

# 3) 호스트 포트 충돌
$port = [int]$cfg.cluster.hostPort
$inUse = $null -ne (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
if ($inUse) { Write-Warn2 ("포트 {0} 이 이미 사용 중입니다 — config/env.dev.json 의 hostPort 를 바꾸세요" -f $port) }
else { Write-Ok ("포트 {0} 사용 가능" -f $port) }
Add-Check ("호스트 포트 {0} 가용" -f $port) (-not $inUse) 'k3d LoadBalancer 매핑용'

# 4) 앱 소스
$app = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$hasDockerfile = Test-Path (Join-Path $app 'Dockerfile')
Add-Check '앱 Dockerfile 존재' $hasDockerfile $app

$ok = New-TestReport -Env 'dev' -Kind 'prereq' -Results $results -OutDir "$PSScriptRoot\reports"
if (-not $ok) { Write-Err2 '전제조건 미충족 — 위 [FAIL] 항목을 먼저 해결하세요.'; exit 1 }
Write-Ok 'dev 전제조건 모두 충족'
