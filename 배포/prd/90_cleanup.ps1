<#  prd 정리 — 실습 종료 시에만. 운영에서는 절대 실행 금지
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\90_cleanup.ps1 [-Force]
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

Write-Step "prd 리소스 정리"
Write-Warn2 '이 스크립트는 「실습으로 만든 운영 모사 환경」을 지우기 위한 것입니다.'
Write-Warn2 '실제 운영 환경에서는 절대 실행하지 마세요.'

Write-Info ("리소스 그룹: " + $RG)
az resource list -g $RG --query "[].{Name:name,Type:type}" -o table 2>$null
$count = az resource list -g $RG --query "length(@)" -o tsv 2>$null
Write-Warn2 ("삭제 대상 {0} 개 — AKS · ACR · PostgreSQL(백업 포함) · Redis · Storage · Key Vault · Log Analytics" -f $count)
Write-Warn2 'PostgreSQL 데이터와 백업이 함께 삭제됩니다. 필요한 데이터는 먼저 내보내세요.'

if (-not (Confirm-Destructive -Target ("운영 리소스 그룹 " + $RG + " 전체") -Force:$Force)) { exit 0 }

# Key Vault 는 소프트 삭제가 남으므로 안내
$kv = az keyvault list -g $RG --query "[0].name" -o tsv 2>$null
Invoke-Checked -What 'az group delete' -Script { az group delete -n $RG --yes --no-wait }
if ($kv) {
    Write-Info ("Key Vault '{0}' 는 소프트 삭제 상태로 남습니다. 완전 삭제: az keyvault purge -n {0}" -f $kv)
}
Write-Ok 'prd 정리 요청 완료 — 포털에서 최종 확인하세요.'
