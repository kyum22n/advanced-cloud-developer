<#  prd 빌드 — ACR 빌드 + 취약점 스캔 + 불변 태그 부여
    환경: prd (Azure AKS + PaaS 데이터·보안·관측 서비스)
    실행: pwsh -File .\30_build.ps1 [-Force]
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

Write-Step "운영 이미지 빌드 (ACR)"

$app = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$acr = $cfg.azure.acrName
$sha = Get-GitSha -Fallback ((Get-Date).ToString('yyyyMMddHHmmss'))
# 운영은 latest 같은 가변 태그를 쓰지 않는다 — 무엇이 배포됐는지 추적 가능해야 한다
$tag = "prd-$sha"
$repo = $cfg.app.image

Write-Info ("소스: " + $app)
Write-Info ("이미지: {0}.azurecr.io/{1}:{2}  (불변 태그)" -f $acr, $repo, $tag)

Invoke-Checked -What 'az acr build' -Script {
    az acr build -r $acr -t ("{0}:{1}" -f $repo, $tag) $app `
        --build-arg BUILD_SHA=$sha --only-show-errors -o none
}

Write-Step "이미지 취약점 스캔 결과 확인 (Defender for Containers)"
Write-Info 'Defender for Containers 가 활성화된 구독이면 아래에서 결과를 확인할 수 있습니다.'
Write-Host '  az security assessment list --query "[?contains(displayName,' + "'container'" + ')]" -o table' -ForegroundColor Gray
Write-Warn2 '스캔에서 High/Critical 이 발견되면 배포를 중단하고 베이스 이미지를 갱신하세요.'

$out = @{ registry = ("{0}.azurecr.io" -f $acr); repository = $repo; tag = $tag; sha = $sha; builtAt = (Get-Date).ToString('s') }
New-Item -ItemType Directory -Force "$PSScriptRoot\reports" | Out-Null
$out | ConvertTo-Json | Out-File "$PSScriptRoot\reports\last-build.json" -Encoding utf8

az acr repository show-tags -n $acr --repository $repo --top 5 --orderby time_desc -o table
Write-Ok ("빌드 완료: {0} — 다음: .\40_deploy.ps1" -f $tag)
