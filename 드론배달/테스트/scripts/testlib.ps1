# 테스트 공통 함수.
#
#   . "$PSScriptRoot\testlib.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tests = @()
$script:CurrentSuite = ''

function Start-Suite {
    param([Parameter(Mandatory)][string]$Name)
    $script:CurrentSuite = $Name
    Write-Host ''
    Write-Host ('─' * 66) -ForegroundColor DarkGray
    Write-Host " $Name" -ForegroundColor Cyan
    Write-Host ('─' * 66) -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    하나의 테스트를 실행하고 결과를 기록한다.

.DESCRIPTION
    실패해도 중단하지 않는다 — 한 테스트의 실패가 나머지를 가리면
    «무엇이 깨졌는지» 전체 그림을 볼 수 없다.
#>
function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $passed = $false
    $detail = ''

    try {
        & $Body
        $passed = $true
    } catch {
        $detail = $_.Exception.Message
    }
    $sw.Stop()

    $script:Tests += [pscustomobject]@{
        suite  = $script:CurrentSuite
        id     = $Id
        name   = $Name
        passed = $passed
        ms     = $sw.ElapsedMilliseconds
        detail = $detail
    }

    if ($passed) {
        Write-Host ("  ✓ [{0}] {1}  ({2}ms)" -f $Id, $Name, $sw.ElapsedMilliseconds) -ForegroundColor Green
    } else {
        Write-Host ("  ✗ [{0}] {1}" -f $Id, $Name) -ForegroundColor Red
        Write-Host ("      {0}" -f $detail) -ForegroundColor DarkRed
    }
}

# ─────────────────────────────────────────── 단언

function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    if ($Expected -ne $Actual) {
        throw "기대값 «$Expected» 이지만 실제는 «$Actual» 입니다. $Because"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Because = '')
    if (-not $Condition) {
        throw "참이어야 하는데 거짓입니다. $Because"
    }
}

function Assert-NotNull {
    param($Value, [string]$Because = '')
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        throw "값이 있어야 하는데 비어 있습니다. $Because"
    }
}

function Assert-StatusCode {
    param([int]$Expected, $Response, [string]$Because = '')
    $actual = if ($null -eq $Response) { 0 } else { [int]$Response.StatusCode }
    if ($actual -ne $Expected) {
        throw "HTTP $Expected 이어야 하는데 $actual 입니다. $Because"
    }
}

function Assert-LessThan {
    param([double]$Limit, [double]$Actual, [string]$Because = '')
    if ($Actual -ge $Limit) {
        throw "$Limit 미만이어야 하는데 $Actual 입니다. $Because"
    }
}

# ─────────────────────────────────────────── HTTP
#
# Invoke-WebRequest 는 4xx·5xx 에서 예외를 던진다.
# 테스트에서는 «409 가 나와야 한다»를 검증해야 하므로 예외를 응답으로 바꾼다.

function Invoke-Api {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        $Body = $null,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 30
    )

    $h = @{ 'Content-Type' = 'application/json' } + $Headers
    if (-not $h.ContainsKey('X-Correlation-Id')) {
        $h['X-Correlation-Id'] = "test-$([guid]::NewGuid().ToString('N').Substring(0,12))"
    }

    $params = @{
        Method             = $Method
        Uri                = $Uri
        Headers            = $h
        TimeoutSec         = $TimeoutSec
        SkipHttpErrorCheck = $true      # ★ 4xx·5xx 도 응답으로 받는다
        ErrorAction        = 'Stop'
    }
    if ($null -ne $Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 8 -Compress)
    }

    try {
        return Invoke-WebRequest @params
    } catch {
        # 연결 자체가 실패한 경우 — 서비스가 떠 있지 않다.
        throw "요청 실패 ($Method $Uri): $($_.Exception.Message)"
    }
}

function Get-JsonBody {
    param($Response)
    if ($null -eq $Response -or [string]::IsNullOrWhiteSpace($Response.Content)) { return $null }
    return $Response.Content | ConvertFrom-Json
}

# ─────────────────────────────────────────── 폴링
#
# 이 시스템은 최종 일관성을 쓴다. «바로 조회하면 없을 수 있다»가 정상이다.
# 그래서 테스트도 «될 때까지 기다린다»로 써야 한다.
# 고정 Start-Sleep 을 쓰면 느린 환경에서 깨지고 빠른 환경에서 느려진다.

function Wait-Until {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [int]$TimeoutSec = 30,
        [int]$IntervalMs = 500,
        [string]$Description = '조건'
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            if (& $Condition) { return $true }
        } catch { }
        Start-Sleep -Milliseconds $IntervalMs
    }
    throw "$Description 이(가) ${TimeoutSec}초 안에 충족되지 않았습니다."
}

# ─────────────────────────────────────────── 결과 저장

function Save-TestResults {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$OutDir
    )
    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    $pass = @($script:Tests | Where-Object { $_.passed }).Count
    $fail = @($script:Tests | Where-Object { -not $_.passed }).Count
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $OutDir "${Name}_$stamp.json"

    [pscustomobject]@{
        name      = $Name
        timestamp = (Get-Date).ToString('o')
        pass      = $pass
        fail      = $fail
        tests     = $script:Tests
    } | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding utf8

    Write-Host ''
    Write-Host ('=' * 66)
    if ($fail -eq 0) {
        Write-Host " 통과 $pass · 실패 0" -ForegroundColor Green
    } else {
        Write-Host " 통과 $pass · 실패 $fail" -ForegroundColor Red
        Write-Host ''
        Write-Host ' 실패한 테스트:'
        foreach ($t in $script:Tests | Where-Object { -not $_.passed }) {
            Write-Host ("   [{0}] {1}" -f $t.id, $t.name) -ForegroundColor Red
            Write-Host ("      {0}" -f $t.detail) -ForegroundColor DarkRed
        }
    }
    Write-Host " 기록: $path"
    return $fail
}

# ─────────────────────────────────────────── 대상 주소 결정

<#
.SYNOPSIS
    테스트 대상 기본 주소를 정한다.

.DESCRIPTION
    ① -BaseUrl 인수가 있으면 그것
    ② 구축/출력/env.{env}.json 이 있으면 거기서 읽기
    ③ 없으면 로컬 기본값
#>
function Resolve-BaseUrls {
    param(
        [string]$Env = 'local',
        [string]$BaseUrl = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
        return @{
            Ingestion = $BaseUrl
            Delivery  = $BaseUrl
            History   = $BaseUrl
            Drone     = $BaseUrl
        }
    }

    $outFile = Join-Path $PSScriptRoot "..\..\구축\출력\env.$Env.json"
    if (Test-Path $outFile) {
        $out = Get-Content $outFile -Raw | ConvertFrom-Json
        $urls = $out.app_urls.value
        return @{
            Ingestion = $urls.ingestion
            Delivery  = $urls.delivery
            History   = $urls.'delivery-history'
            Drone     = $urls.'drone-scheduler'
        }
    }

    # 로컬 — 각 서비스를 직접 띄운 경우
    return @{
        Ingestion = 'http://localhost:8081'
        Delivery  = 'http://localhost:8083'
        History   = 'http://localhost:8086'
        Drone     = 'http://localhost:8085'
    }
}

function New-IdempotencyKey {
    return [guid]::NewGuid().ToString()
}

function New-TestDeliveryRequest {
    param([string]$OwnerId = 'acc-test-0001', [double]$WeightKg = 2.5, [string]$Size = 'SMALL')
    $now = (Get-Date).ToUniversalTime()
    return @{
        ownerId = $OwnerId
        # 가상 좌표 — 실제 주소를 쓰지 않는다 (실습 안전 수칙)
        pickup  = @{ latitude = 37.5665; longitude = 126.9780; altitude = 0 }
        dropoff = @{ latitude = 37.5172; longitude = 127.0473; altitude = 0 }
        pickupWindow = @{
            earliest = $now.AddMinutes(10).ToString('o')
            latest   = $now.AddMinutes(60).ToString('o')
        }
        packageInfo = @{
            weight      = $WeightKg
            unit        = 'KG'
            size        = $Size
            description = '통합 테스트용 가상 패키지'
        }
    }
}
