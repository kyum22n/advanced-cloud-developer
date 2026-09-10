<#
.SYNOPSIS
    E2E 테스트 — 사용자 관점의 전체 여정.

.DESCRIPTION
    통합 테스트가 «서비스 사이»를 본다면, E2E 는 «사용자가 하는 일»을 그대로 한다.

      예약한다 → 배달 번호를 받는다 → 추적한다 → 드론이 움직인다 → 이력을 본다

    이 테스트가 통과하면 «시스템이 사업적으로 동작한다»고 말할 수 있다.

.EXAMPLE
    .\50_delivery_journey.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [string]$Env = 'local',
    [string]$BaseUrl = '',
    [int]$TimeoutSec = 60
)

. "$PSScriptRoot\..\scripts\testlib.ps1"

$urls = Resolve-BaseUrls -Env $Env -BaseUrl $BaseUrl

# 여정 전체가 하나의 상관 ID 를 공유한다 — 실패했을 때 로그를 이 ID 로 한 번에 찾는다.
$journeyId = "e2e-$([guid]::NewGuid().ToString('N').Substring(0,12))"
$headers = @{ 'X-Correlation-Id' = $journeyId }

Write-Host ''
Write-Host " 여정 상관 ID: $journeyId" -ForegroundColor DarkGray
Write-Host ' 실패하면 이 ID 로 Application Insights 를 검색하세요.' -ForegroundColor DarkGray

$deliveryId = $null

Start-Suite 'E2E — 배달 여정'

Test-Case 'E2E-01' '① 사용자가 배달을 예약한다' {
    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body (New-TestDeliveryRequest) `
        -Headers ($headers + @{ 'Idempotency-Key' = (New-IdempotencyKey) })

    Assert-StatusCode 202 $r
    $body = Get-JsonBody $r
    $script:deliveryId = $body.deliveryId
    Assert-NotNull $script:deliveryId

    Write-Host ("      배달 번호: {0}" -f $script:deliveryId) -ForegroundColor DarkGray
}

Test-Case 'E2E-02' '② 잠시 후 추적 화면에서 배달이 보인다' {
    Wait-Until -TimeoutSec $TimeoutSec -Description '배달 생성' -Condition {
        $r = Invoke-Api -Method GET `
            -Uri "$($urls.Delivery)/api/v1/deliveries/$($script:deliveryId)/status" `
            -Headers $headers
        $r.StatusCode -eq 200
    }
}

Test-Case 'E2E-03' '③ 배달에 드론이 배정되거나 타사로 위탁된다' {
    Wait-Until -TimeoutSec $TimeoutSec -Description '처리 진행' -Condition {
        $r = Invoke-Api -Method GET `
            -Uri "$($urls.Delivery)/api/v1/deliveries/$($script:deliveryId)/status" `
            -Headers $headers
        if ($r.StatusCode -ne 200) { return $false }
        (Get-JsonBody $r).status -ne 'PENDING'
    }

    $r = Invoke-Api -Method GET `
        -Uri "$($urls.Delivery)/api/v1/deliveries/$($script:deliveryId)/status" -Headers $headers
    $s = Get-JsonBody $r
    Write-Host ("      상태: {0}" -f $s.status) -ForegroundColor DarkGray
}

Test-Case 'E2E-04' '④ ETA 가 계산되어 표시된다' {
    Wait-Until -TimeoutSec $TimeoutSec -Description 'ETA 산출' -Condition {
        $r = Invoke-Api -Method GET `
            -Uri "$($urls.Delivery)/api/v1/deliveries/$($script:deliveryId)/status" `
            -Headers $headers
        if ($r.StatusCode -ne 200) { return $false }
        $null -ne (Get-JsonBody $r).eta
    }

    $r = Invoke-Api -Method GET `
        -Uri "$($urls.Delivery)/api/v1/deliveries/$($script:deliveryId)/status" -Headers $headers
    $eta = (Get-JsonBody $r).eta

    # ETA 는 «지금보다 미래»여야 한다 (INV-06).
    $arrival = [datetime]::Parse($eta.arrivalTime).ToUniversalTime()
    Assert-True ($arrival -gt (Get-Date).ToUniversalTime().AddSeconds(-60)) `
        'ETA 가 과거를 가리키고 있습니다'

    Write-Host ("      ETA: {0:HH:mm} · 신뢰도 {1:P0}" -f $arrival.ToLocalTime(), $eta.confidence) -ForegroundColor DarkGray
}

Test-Case 'E2E-05' '⑤ 배달 이력이 조회된다' {
    Wait-Until -TimeoutSec $TimeoutSec -Description '이력 적재' -Condition {
        $r = Invoke-Api -Method GET `
            -Uri "$($urls.History)/api/v1/history/$($script:deliveryId)" -Headers $headers
        $r.StatusCode -eq 200
    }

    $r = Invoke-Api -Method GET `
        -Uri "$($urls.History)/api/v1/history/$($script:deliveryId)" -Headers $headers
    $h = Get-JsonBody $r

    Assert-Equal $script:deliveryId $h.deliveryId
    Assert-True ($h.milestones.Count -ge 1) '이정표가 하나도 없습니다'

    Write-Host ("      이정표 {0}개" -f $h.milestones.Count) -ForegroundColor DarkGray
    foreach ($m in $h.milestones) {
        Write-Host ("        · {0}" -f $m.eventType) -ForegroundColor DarkGray
    }
}

Start-Suite 'E2E — 취소 여정'

Test-Case 'E2E-06' '사용자가 배달을 취소한다' {
    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body (New-TestDeliveryRequest) `
        -Headers ($headers + @{ 'Idempotency-Key' = (New-IdempotencyKey) })
    $cancelId = (Get-JsonBody $r).deliveryId

    Wait-Until -TimeoutSec $TimeoutSec -Description '배달 생성' -Condition {
        (Invoke-Api -Method GET `
            -Uri "$($urls.Delivery)/api/v1/deliveries/$cancelId/status" -Headers $headers
        ).StatusCode -eq 200
    }

    $status = (Get-JsonBody (Invoke-Api -Method GET `
        -Uri "$($urls.Delivery)/api/v1/deliveries/$cancelId/status" -Headers $headers)).status

    $r = Invoke-Api -Method DELETE `
        -Uri "$($urls.Delivery)/api/v1/deliveries/$cancelId`?reason=사용자요청" -Headers $headers

    # 취소 가능한 상태였다면 성공, 아니면 409 — 둘 다 «올바른» 결과다.
    Assert-True ($r.StatusCode -in @(200, 409)) `
        "취소 응답이 200 또는 409 여야 하는데 $($r.StatusCode) 입니다"

    if ($r.StatusCode -eq 200) {
        Write-Host "      $status 상태에서 취소 성공" -ForegroundColor DarkGray
    } else {
        Write-Host "      $status 상태라 취소 거부 (INV-01 — 올바른 동작)" -ForegroundColor DarkGray
    }
}

exit (Save-TestResults -Name "e2e_$Env" -OutDir (Join-Path $PSScriptRoot '..\결과'))
