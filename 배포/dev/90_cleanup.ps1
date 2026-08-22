<#  dev 정리 — 클러스터·이미지 제거 (되돌릴 수 없음)
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\90_cleanup.ps1 [-Force]
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

Write-Step "dev 환경 정리"

Write-Info '삭제 대상:'
Write-Host ("  - k3d 클러스터: " + $cfg.cluster.name) -ForegroundColor Yellow
Write-Host ("  - 네임스페이스: " + $cfg.app.namespace + " (클러스터와 함께 제거됨)") -ForegroundColor Yellow
Write-Host ("  - 로컬 이미지: " + $cfg.app.image + ":*") -ForegroundColor Yellow

if (-not (Confirm-Destructive -Target ("k3d 클러스터 " + $cfg.cluster.name) -Force:$Force)) { exit 0 }

$exists = (k3d cluster list -o json | ConvertFrom-Json) | Where-Object { $_.name -eq $cfg.cluster.name }
if ($exists) {
    Invoke-Checked -What 'k3d cluster delete' -Script { k3d cluster delete $cfg.cluster.name }
} else { Write-Info '클러스터가 이미 없습니다.' }

$imgs = docker images --format "{{.Repository}}:{{.Tag}}" | Where-Object { $_ -like ($cfg.app.image + ":*") }
if ($imgs) { foreach ($i in $imgs) { docker rmi -f $i 2>$null | Out-Null }; Write-Ok ("이미지 {0} 개 삭제" -f $imgs.Count) }

Write-Ok 'dev 정리 완료. (docker system df 로 잔여 용량을 확인할 수 있습니다)'
