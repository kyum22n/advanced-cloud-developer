<#
.SYNOPSIS
    계약 테스트 — API 가 OpenAPI 명세대로 응답하는가.

.DESCRIPTION
    「문서와 실제가 다르다」는 마이크로서비스에서 가장 흔한 사고다.
    문서를 보고 만든 클라이언트가 런타임에 깨진다.

    이 테스트는 «실제 응답»을 «약속한 계약»과 대조한다.
      · 필수 필드가 있는가
      · 오류가 RFC 9457 Problem Details 형식인가
      · 상태 코드가 규약대로인가 (400 / 409 / 412 구분)

.EXAMPLE
    .\20_contract.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [string]$Env = 'local',
    [string]$BaseUrl = ''
)

. "$PSScriptRoot\..\scripts\testlib.ps1"

$urls = Resolve-BaseUrls -Env $Env -BaseUrl $BaseUrl

Start-Suite '계약 — 요청 형식'

Test-Case 'CT-01' 'Idempotency-Key 없는 POST 는 400 을 낸다' {
    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body (New-TestDeliveryRequest)
    Assert-StatusCode 400 $r '공개 POST 는 멱등 키를 요구해야 합니다'

    $body = Get-JsonBody $r
    Assert-NotNull $body.type   'Problem Details 의 type 이 없습니다'
    Assert-NotNull $body.title  'Problem Details 의 title 이 없습니다'
}

Test-Case 'CT-02' '필수 필드가 없으면 400 과 필드 오류 목록을 낸다' {
    $bad = New-TestDeliveryRequest
    $bad.Remove('ownerId')

    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body $bad -Headers @{ 'Idempotency-Key' = (New-IdempotencyKey) }
    Assert-StatusCode 400 $r

    $body = Get-JsonBody $r
    Assert-NotNull $body.errors '어느 필드가 잘못됐는지 알려 줘야 합니다'
}

Test-Case 'CT-03' '무게가 0 이하면 400 을 낸다' {
    $bad = New-TestDeliveryRequest -WeightKg 0
    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body $bad -Headers @{ 'Idempotency-Key' = (New-IdempotencyKey) }
    Assert-StatusCode 400 $r
}

Test-Case 'CT-04' '좌표가 범위를 벗어나면 400 을 낸다' {
    $bad = New-TestDeliveryRequest
    $bad.pickup.latitude = 200
    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body $bad -Headers @{ 'Idempotency-Key' = (New-IdempotencyKey) }
    Assert-StatusCode 400 $r
}

Start-Suite '계약 — 응답 형식'

Test-Case 'CT-05' '접수는 202 와 deliveryId · statusUrl 을 돌려준다' {
    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body (New-TestDeliveryRequest) `
        -Headers @{ 'Idempotency-Key' = (New-IdempotencyKey) }

    # ★ 201 이 아니라 202 — 접수했을 뿐 아직 만들어지지 않았다.
    Assert-StatusCode 202 $r '비동기 접수는 202 Accepted 여야 합니다'

    $body = Get-JsonBody $r
    Assert-NotNull $body.deliveryId
    Assert-NotNull $body.statusUrl  '클라이언트가 어디를 폴링할지 알려 줘야 합니다'
    Assert-NotNull $r.Headers['Location'] 'Location 헤더가 있어야 합니다'
    Assert-NotNull $r.Headers['Retry-After'] '언제 다시 물어볼지 알려 줘야 합니다'
}

Test-Case 'CT-06' '없는 배달을 조회하면 404 와 Problem Details 를 낸다' {
    $r = Invoke-Api -Method GET -Uri "$($urls.Delivery)/api/v1/deliveries/dlv-does-not-exist"
    Assert-StatusCode 404 $r

    $body = Get-JsonBody $r
    Assert-NotNull $body.type
    Assert-True ($r.Headers['Content-Type'] -match 'problem\+json') `
        'Content-Type 이 application/problem+json 이어야 합니다'
}

Test-Case 'CT-07' '모든 응답에 상관 ID 가 되돌아온다' {
    $correlationId = "test-$([guid]::NewGuid().ToString('N').Substring(0,12))"
    $r = Invoke-Api -Method GET -Uri "$($urls.Delivery)/api/v1/deliveries/dlv-x" `
        -Headers @{ 'X-Correlation-Id' = $correlationId }

    Assert-Equal $correlationId $r.Headers['X-Correlation-Id'][0] `
        '보낸 상관 ID 가 그대로 돌아와야 추적이 이어집니다'
}

Start-Suite '계약 — 멱등성 (AC-2)'

Test-Case 'CT-08' '같은 멱등 키로 재요청하면 같은 배달 ID 를 준다' {
    $key = New-IdempotencyKey
    $request = New-TestDeliveryRequest

    $first  = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body $request -Headers @{ 'Idempotency-Key' = $key }
    $second = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body $request -Headers @{ 'Idempotency-Key' = $key }

    Assert-StatusCode 202 $first
    Assert-StatusCode 202 $second
    Assert-Equal (Get-JsonBody $first).deliveryId (Get-JsonBody $second).deliveryId `
        '재시도가 배달을 두 번 만들면 안 됩니다'
}

Test-Case 'CT-09' '같은 멱등 키로 다른 내용을 보내면 422 를 낸다' {
    $key = New-IdempotencyKey

    $a = New-TestDeliveryRequest -WeightKg 2.5
    $b = New-TestDeliveryRequest -WeightKg 3.5

    Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body $a -Headers @{ 'Idempotency-Key' = $key } | Out-Null

    $r = Invoke-Api -Method POST -Uri "$($urls.Ingestion)/api/v1/deliveries" `
        -Body $b -Headers @{ 'Idempotency-Key' = $key }

    # 422 — 형식은 맞지만 처리할 수 없다. 400 과 구분해야 한다.
    Assert-StatusCode 422 $r '키 재사용은 400 이 아니라 422 입니다'
}

exit (Save-TestResults -Name "contract_$Env" -OutDir (Join-Path $PSScriptRoot '..\결과'))
