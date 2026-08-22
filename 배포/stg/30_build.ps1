<#  stg 빌드 — ACR 클라우드 빌드로 이미지 생성·푸시
    환경: stg (Azure AKS + Argo CD GitOps)
    실행: pwsh -File .\30_build.ps1 [-Force]
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

Write-Step "ACR 클라우드 빌드 (로컬 Docker 불필요)"

$app = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$acr = $cfg.azure.acrName
$sha = Get-GitSha -Fallback ((Get-Date).ToString('yyyyMMddHHmmss'))
$tag = "stg-$sha"
$repo = $cfg.app.image

Write-Info ("소스: " + $app)
Write-Info ("이미지: {0}.azurecr.io/{1}:{2}" -f $acr, $repo, $tag)

# az acr build — 소스를 ACR 로 보내 클라우드에서 빌드·푸시한다(로컬 Docker 엔진 불필요)
Invoke-Checked -What 'az acr build' -Script {
    az acr build -r $acr -t ("{0}:{1}" -f $repo, $tag) -t ("{0}:stg-latest" -f $repo) $app --only-show-errors -o none
}

# 취약점·태그 확인
Write-Step "이미지 확인"
az acr repository show-tags -n $acr --repository $repo --top 5 --orderby time_desc -o table

$out = @{ registry = ("{0}.azurecr.io" -f $acr); repository = $repo; tag = $tag; sha = $sha; builtAt = (Get-Date).ToString('s') }
New-Item -ItemType Directory -Force "$PSScriptRoot\reports" | Out-Null
$out | ConvertTo-Json | Out-File "$PSScriptRoot\reports\last-build.json" -Encoding utf8

Write-Ok ("빌드·푸시 완료: {0} — 다음: .\40_deploy.ps1 (GitOps 동기화)" -f $tag)
