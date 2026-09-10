<#
.SYNOPSIS
    스모크 테스트 — 「서비스가 살아 있는가」만 확인한다.

.DESCRIPTION
    가장 먼저 돌린다. 여기서 실패하면 다른 테스트를 돌릴 이유가 없다.
    상태 프로브만 보므로 데이터를 만들지 않는다.

.EXAMPLE
    .\10_smoke.ps1 -Env dev
    .\10_smoke.ps1 -BaseUrl http://localhost:8081
#>
[CmdletBinding()]
param(
    [string]$Env = 'local',
    [string]$BaseUrl = ''
)

. "$PSScriptRoot\..\scripts\testlib.ps1"

$urls = Resolve-BaseUrls -Env $Env -BaseUrl $BaseUrl

Start-Suite '스모크 — 서비스 생존 확인'

$services = @(
    @{ Id = 'SM-01'; Name = 'Ingestion';        Url = $urls.Ingestion }
    @{ Id = 'SM-02'; Name = 'Delivery';         Url = $urls.Delivery }
    @{ Id = 'SM-03'; Name = 'Delivery History'; Url = $urls.History }
    @{ Id = 'SM-04'; Name = 'Drone Scheduler';  Url = $urls.Drone }
)

foreach ($s in $services) {
    if ([string]::IsNullOrWhiteSpace($s.Url)) {
        Write-Host ("  - [{0}] {1} — 주소를 알 수 없어 건너뜁니다" -f $s.Id, $s.Name) -ForegroundColor DarkGray
        continue
    }

    Test-Case $s.Id "$($s.Name) 활성 프로브" {
        $r = Invoke-Api -Method GET -Uri "$($s.Url)/actuator/health/liveness" -TimeoutSec 10
        Assert-StatusCode 200 $r "$($s.Name) 이(가) 응답하지 않습니다"
    }

    Test-Case "$($s.Id)-R" "$($s.Name) 준비 프로브" {
        $r = Invoke-Api -Method GET -Uri "$($s.Url)/actuator/health/readiness" -TimeoutSec 10
        Assert-StatusCode 200 $r "$($s.Name) 의 의존 자원 연결이 준비되지 않았습니다"
    }
}

# ⚠️ 운영 환경에서 Swagger UI 가 열려 있으면 안 된다 (SEC-15).
if ($Env -eq 'prd') {
    Test-Case 'SM-SEC' 'prd 에서 Swagger UI 차단' {
        $r = Invoke-Api -Method GET -Uri "$($urls.Ingestion)/swagger-ui.html" -TimeoutSec 10
        Assert-True ($r.StatusCode -ge 400) '운영 환경에서 API 문서가 공개되어 있습니다'
    }
}

exit (Save-TestResults -Name "smoke_$Env" -OutDir (Join-Path $PSScriptRoot '..\결과'))
