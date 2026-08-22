<#  stg 정리 — 리소스 그룹 단위 삭제 (되돌릴 수 없음)
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\90_cleanup.ps1 [-Force]
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

Write-Step "stg 리소스 정리"

Write-Info ("리소스 그룹: " + $RG)
az resource list -g $RG -o table 2>$null
$count = (az resource list -g $RG --query "length(@)" -o tsv 2>$null)
Write-Warn2 ("삭제 대상 리소스 {0} 개 (AKS · ACR · LoadBalancer 공용 IP · 디스크 포함)" -f $count)

if (-not (Confirm-Destructive -Target ("리소스 그룹 " + $RG) -Force:$Force)) { exit 0 }

Invoke-Checked -What 'az group delete' -Script { az group delete -n $RG --yes --no-wait }
Write-Info '삭제는 백그라운드로 진행됩니다. 확인: az group exists -n ' + $RG
Write-Ok 'stg 정리 요청 완료 — 몇 분 뒤 포털에서 최종 확인하세요.'
