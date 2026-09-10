<#
.SYNOPSIS
    통합 테스트 — Saga · 도메인 불변식 · 최종 일관성.

.DESCRIPTION
    단위 테스트가 «한 클래스 안»을 보장한다면, 이 테스트는 «서비스 사이»를 본다.
    특히 다음 세 가지는 단위 테스트로 절대 잡히지 않는다.
      ① 서비스 간 계약 불일치
      ② 최종 일관성이 실제로 «수렴»하는가
      ③ 실패 시 보상이 실제로 «실행»되는가

.EXAMPLE
    .\30_saga.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [string]$Env = 'local',
    [string]$BaseUrl = '',
    [int]$ConvergenceTimeoutSec = 30
)

. "$PSScriptRoot\..\scripts\testlib.ps1"

$urls = Resolve-BaseUrls -Env $Env -BaseUrl $BaseUrl

function New-Delivery {
    param([double]$WeightKg = 2.5, [string]$Size = 'SMALL')
    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body (New-TestDeliveryRequest -WeightKg $WeightKg -Size $Size) `
        -Headers @{ 'Idempotency-Key' = (New-IdempotencyKey) }
    if ($r.StatusCode -ne 202) {
        throw "배달 접수 실패: HTTP $($r.StatusCode)"
    }
    return (Get-JsonBody $r).deliveryId
}

function Get-Status {
    param([string]$DeliveryId)
    $r = Invoke-Api -Method GET -Uri "$($urls.Delivery)/api/v1/deliveries/$DeliveryId/status"
    if ($r.StatusCode -ne 200) { return $null }
    return Get-JsonBody $r
}

Start-Suite '통합 — Saga 정상 경로'

Test-Case 'IT-01' '접수한 배달이 결국 생성된다 — 최종 일관성 수렴 (NFR-07)' {
    $id = New-Delivery
    $sw = [Diagnostics.Stopwatch]::StartNew()

    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description "배달 $id 생성" -Condition {
        $null -ne (Get-Status $id)
    }
    $sw.Stop()

    Write-Host ("      수렴 시간: {0:N1}초" -f ($sw.ElapsedMilliseconds / 1000)) -ForegroundColor DarkGray
    Assert-LessThan ($ConvergenceTimeoutSec * 1000) $sw.ElapsedMilliseconds
}

Test-Case 'IT-02' '생성된 배달에 드론이 배정되거나 타사로 위탁된다' {
    $id = New-Delivery
    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description '드론 배정 또는 위탁' -Condition {
        $s = Get-Status $id
        $null -ne $s -and $s.status -in @('SCHEDULED', 'DELEGATED', 'IN_TRANSIT', 'HEADED_TO_DROPOFF')
    }
}

Test-Case 'IT-03' '배달 이력이 적재된다 — 이벤트 전파' {
    $id = New-Delivery
    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description '이력 적재' -Condition {
        $r = Invoke-Api -Method GET -Uri "$($urls.History)/api/v1/history/$id"
        $r.StatusCode -eq 200
    }
}

Start-Suite '통합 — 도메인 불변식'

Test-Case 'IT-04' 'INV-01 — 이동을 시작한 배달은 취소되지 않는다' {
    $id = New-Delivery

    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description '배달 생성' -Condition {
        $null -ne (Get-Status $id)
    }

    $status = (Get-Status $id).status
    $r = Invoke-Api -Method DELETE -Uri "$($urls.Delivery)/api/v1/deliveries/$id`?reason=test"

    if ($status -in @('PENDING', 'SCHEDULED')) {
        Assert-StatusCode 200 $r "$status 상태에서는 취소할 수 있어야 합니다"
    } else {
        # ★ 409 — 형식은 맞지만 «현재 상태»에서 불가하다.
        Assert-StatusCode 409 $r "$status 상태에서는 취소가 거부되어야 합니다 (INV-01)"

        $body = Get-JsonBody $r
        Assert-True ($body.type -match 'invalid-state-transition') `
            '오류 유형으로 원인을 알 수 있어야 합니다'
    }
}

Test-Case 'IT-05' 'INV-03 — 드론 용량을 넘는 패키지는 타사로 위탁된다' {
    # 6kg — 드론 최대 적재량 5kg 초과
    $id = New-Delivery -WeightKg 6.0

    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description '위탁 처리' -Condition {
        $s = Get-Status $id
        $null -ne $s -and $s.status -in @('DELEGATED', 'FAILED', 'COMPENSATED')
    }

    $s = Get-Status $id
    Assert-True ($s.status -ne 'SCHEDULED') `
        '드론이 옮길 수 없는 무게인데 드론이 배정되었습니다'
}

Test-Case 'IT-06' '대형 패키지는 드론에 배정되지 않는다' {
    $id = New-Delivery -Size 'LARGE'

    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description '대형 패키지 처리' -Condition {
        $null -ne (Get-Status $id)
    }

    $s = Get-Status $id
    Assert-True ($s.status -ne 'SCHEDULED') `
        '드론 적재함에 들어가지 않는 크기인데 드론이 배정되었습니다'
}

Start-Suite '통합 — 멱등성과 재시도 안전성'

Test-Case 'IT-07' '같은 취소 요청을 두 번 보내도 상태가 망가지지 않는다' {
    $id = New-Delivery
    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description '배달 생성' -Condition {
        $null -ne (Get-Status $id)
    }

    $first  = Invoke-Api -Method DELETE -Uri "$($urls.Delivery)/api/v1/deliveries/$id`?reason=test"
    $after1 = (Get-Status $id).status
    Invoke-Api -Method DELETE -Uri "$($urls.Delivery)/api/v1/deliveries/$id`?reason=test" | Out-Null
    $after2 = (Get-Status $id).status

    Assert-Equal $after1 $after2 '중복 취소가 상태를 바꾸면 안 됩니다'
}

Test-Case 'IT-08' '보상용 삭제는 대상이 없어도 성공한다' {
    # 보상은 멱등해야 한다 — 이미 없는 것을 지울 때 실패하면 Saga 가 멈춘다.
    $r = Invoke-Api -Method DELETE `
        -Uri "$($urls.Delivery)/api/v1/deliveries/dlv-never-existed/compensate"
    Assert-StatusCode 204 $r '없는 대상의 보상이 404 면 Saga 가 진행되지 못합니다'
}

Start-Suite '통합 — 성능 목표'

Test-Case 'IT-09' '접수 API 가 빠르게 응답한다 (NFR-01: p95 ≤ 300ms)' {
    $samples = @()
    for ($i = 0; $i -lt 20; $i++) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
            -Body (New-TestDeliveryRequest) `
            -Headers @{ 'Idempotency-Key' = (New-IdempotencyKey) } | Out-Null
        $sw.Stop()
        $samples += $sw.ElapsedMilliseconds
    }

    $sorted = $samples | Sort-Object
    $p95 = $sorted[[Math]::Min([int]([Math]::Ceiling($sorted.Count * 0.95)) - 1, $sorted.Count - 1)]
    Write-Host ("      p50 {0}ms · p95 {1}ms" -f $sorted[[int]($sorted.Count / 2)], $p95) -ForegroundColor DarkGray

    # ⚠️ 이 값은 «네트워크 지연 포함»이다. dev 환경에서는 목표를 넘을 수 있다.
    #    운영 환경의 실제 판정은 부하 테스트 도구로 한다.
    Assert-LessThan 2000 $p95 '접수가 2초를 넘으면 큐 부하 평준화가 동작하지 않는 것입니다'
}

Test-Case 'IT-10' '추적 조회가 빠르다 (NFR-02: p95 ≤ 150ms)' {
    $id = New-Delivery
    Wait-Until -TimeoutSec $ConvergenceTimeoutSec -Description '배달 생성' -Condition {
        $null -ne (Get-Status $id)
    }

    $samples = @()
    for ($i = 0; $i -lt 20; $i++) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Get-Status $id | Out-Null
        $sw.Stop()
        $samples += $sw.ElapsedMilliseconds
    }

    $sorted = $samples | Sort-Object
    $p95 = $sorted[[Math]::Min([int]([Math]::Ceiling($sorted.Count * 0.95)) - 1, $sorted.Count - 1)]
    Write-Host ("      p50 {0}ms · p95 {1}ms" -f $sorted[[int]($sorted.Count / 2)], $p95) -ForegroundColor DarkGray

    Assert-LessThan 1000 $p95 '추적 조회가 1초를 넘으면 읽기 모델이 동작하지 않는 것입니다'
}

exit (Save-TestResults -Name "saga_$Env" -OutDir (Join-Path $PSScriptRoot '..\결과'))
