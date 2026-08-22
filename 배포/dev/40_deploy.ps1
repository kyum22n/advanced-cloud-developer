<#  dev 배포 — 매니페스트 적용 후 롤아웃 완료까지 대기
    환경: dev (로컬 k3d on Docker Desktop)
    실행: pwsh -File .\40_deploy.ps1 [-Force]
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

Write-Step "애플리케이션 배포"

$ns = $cfg.app.namespace
$buildFile = "$PSScriptRoot\reports\last-build.json"
$tag = $cfg.app.tag
if (Test-Path $buildFile) {
    $b = Get-Content $buildFile -Raw | ConvertFrom-Json
    $tag = $b.tag
    Write-Info ("직전 빌드 태그 사용: " + $tag)
} else {
    Write-Warn2 "빌드 기록이 없어 기본 태그를 사용합니다. 먼저 .\30_build.ps1 을 실행하세요."
}

Invoke-Checked -What '앱 매니페스트 적용' -Script { kubectl apply -f "$PSScriptRoot\config\k8s\app.yaml" }

# 이미지 태그와 버전 환경 변수를 이번 빌드로 교체
Invoke-Checked -What '이미지 태그 지정' -Script {
    kubectl set image deploy/$($cfg.app.name) $($cfg.app.name)="$($cfg.app.image):$tag" -n $ns
}
Invoke-Checked -What 'APP_VERSION 주입' -Script {
    kubectl set env deploy/$($cfg.app.name) APP_VERSION=$tag -n $ns
}
Invoke-Checked -What '롤아웃 완료 대기' -Script {
    kubectl rollout status deploy/$($cfg.app.name) -n $ns --timeout=180s
}

$url = $cfg.test.baseUrl
Write-Step "접속 확인"
Wait-Condition -What ("서비스 응답 " + $url) -TimeoutSec 120 -IntervalSec 5 -Condition { Test-HttpOk -Url ($url + "/healthz") }

Write-Ok ("배포 완료 — 브라우저에서 {0} 을 열어 보세요. 다음: .\50_test_unit.ps1" -f $url)
