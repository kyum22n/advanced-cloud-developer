<#  dev 배포 검증 — 리소스 상태·프로브·엔드포인트 종합 점검
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\80_verify.ps1 [-Force]
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

Write-Step "배포 검증 (Verify)"

$ns   = $cfg.app.namespace
$base = $cfg.test.baseUrl
$results = @()
function Add-V { param($n, $ok, $d) $script:results += [ordered]@{ Name=$n; Status=$(if($ok){'Pass'}else{'Fail'}); Detail=$d } }

# 1) Deployment 준비 상태
$dep = kubectl get deploy $cfg.app.name -n $ns -o json 2>$null | ConvertFrom-Json
$ready = $dep -and $dep.status.readyReplicas -ge 1
Add-V 'Deployment readyReplicas >= 1' $ready ("ready=" + $(if($dep){$dep.status.readyReplicas}else{'n/a'}))

# 2) 파드 Running
$pods = kubectl get pods -n $ns -l app=$($cfg.app.name) -o json 2>$null | ConvertFrom-Json
$running = $pods -and ($pods.items | Where-Object { $_.status.phase -eq 'Running' }).Count -ge 1
Add-V '파드 Running' $running ("pods=" + $(if($pods){$pods.items.Count}else{0}))

# 3) 재시작 횟수(크래시 루프 감지)
$restarts = 0
if ($pods) { foreach ($p in $pods.items) { foreach ($c in $p.status.containerStatuses) { $restarts += $c.restartCount } } }
Add-V '컨테이너 재시작 3회 미만' ($restarts -lt 3) ("restarts=$restarts")

# 4) 엔드포인트 3종
foreach ($ep in @('/healthz', '/readyz', '/version')) {
    Add-V ("엔드포인트 " + $ep) (Test-HttpOk -Url ($base + $ep)) ($base + $ep)
}

# 5) 배포된 버전이 직전 빌드와 일치하는가
$expect = $null
if (Test-Path "$PSScriptRoot\reports\last-build.json") { $expect = (Get-Content "$PSScriptRoot\reports\last-build.json" -Raw | ConvertFrom-Json).tag }
$actual = $null
try { $actual = (Invoke-WebRequest ($base + '/version') -UseBasicParsing).Content | ConvertFrom-Json | Select-Object -ExpandProperty version } catch { }
Add-V '배포 버전 = 직전 빌드 태그' ($expect -and $actual -eq $expect) ("expect=$expect actual=$actual")

$ok = New-TestReport -Env 'dev' -Kind 'verify' -Results $results -OutDir "$PSScriptRoot\reports"
Write-Host ""
kubectl get all -n $ns
if (-not $ok) { exit 1 }
Write-Ok 'dev 배포 검증 통과'
