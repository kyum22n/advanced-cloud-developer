<#  dev 빌드 — 컨테이너 이미지 빌드 후 k3d 클러스터로 반입
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\30_build.ps1 [-Force]
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

Write-Step "앱 이미지 빌드"

$app  = Resolve-AppPath -AppPath $AppPath -RepoRoot $RepoRoot
$sha  = Get-GitSha -Fallback 'local'
$tag  = "$($cfg.app.tag)-$sha"
$img  = "$($cfg.app.image):$tag"
$imgLatest = "$($cfg.app.image):$($cfg.app.tag)"

Write-Info ("소스: " + $app)
Write-Info ("이미지: " + $img)

Invoke-Checked -What 'docker build' -Script {
    docker build -t $img -t $imgLatest --label "env=dev" --label "git-sha=$sha" $app
}

Write-Step "k3d 클러스터로 이미지 반입 (레지스트리 없이)"
Invoke-Checked -What 'k3d image import' -Script {
    k3d image import $img $imgLatest -c $cfg.cluster.name
}

# 배포 단계에서 사용할 태그를 남긴다
$out = @{ image = $img; tag = $tag; sha = $sha; builtAt = (Get-Date).ToString('s') }
New-Item -ItemType Directory -Force "$PSScriptRoot\reports" | Out-Null
$out | ConvertTo-Json | Out-File "$PSScriptRoot\reports\last-build.json" -Encoding utf8

Write-Ok ("빌드 완료: {0} — 다음: .\40_deploy.ps1" -f $img)
