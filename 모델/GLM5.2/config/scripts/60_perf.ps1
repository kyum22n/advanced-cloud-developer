<#  GLM 60 성능 — TTFT · TPOT · 처리량 · 포화점 (06 §3)

    포화점(동시성을 올릴 때 TTFT 가 급증하는 지점)이 HPA 임계값의 근거가 된다.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\..\env.glm.json",
    [string]$BaseUrl = 'http://localhost:8000',
    [int]$MaxTokens = 128
)

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$model = Get-GlmModel
$results = @()
function Add-R { param($n, $ok, $d) $script:results += [ordered]@{ Name = $n; Status = $(if ($ok) { 'Pass' } else { 'Fail' }); Detail = $d } }

$prompt = '클라우드 네이티브 애플리케이션의 핵심 특징을 세 가지로 설명해줘.'

function Measure-One {
    param([int]$Tokens)
    $body = @{ model = $model.modelId; max_tokens = $Tokens; temperature = 0
        messages = @(@{ role = 'user'; content = $prompt }) } | ConvertTo-Json -Depth 6
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $res = Invoke-WebRequest -Uri ($BaseUrl + '/v1/chat/completions') -Method POST `
        -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 300 -SkipHttpErrorCheck
    $sw.Stop()
    if ($res.StatusCode -ne 200) { return $null }
    $j = $res.Content | ConvertFrom-Json
    [pscustomobject]@{
        totalMs = $sw.Elapsed.TotalMilliseconds
        outTokens = $j.usage.completion_tokens
        inTokens = $j.usage.prompt_tokens
    }
}

Write-Step ("워밍업 " + $cfg.test.warmupRequests + "회")
1..$cfg.test.warmupRequests | ForEach-Object { Measure-One -Tokens 32 | Out-Null }
Write-Ok '워밍업 완료'

Write-Step "단일 요청 지연"
$single = Measure-One -Tokens $MaxTokens
if (-not $single) {
    Add-R 'G-P-01 단일 요청' $false '요청 실패'
} else {
    $tpot = if ($single.outTokens -gt 1) { $single.totalMs / $single.outTokens } else { $single.totalMs }
    Write-Info ("총 {0:N0} ms · 출력 {1} 토큰 · 토큰당 {2:N1} ms" -f $single.totalMs, $single.outTokens, $tpot)
    Add-R 'G-P-02 TPOT 목표 이내' ($tpot -le $model.targets.tpotMillis) `
        ("측정 {0:N1} ms / 목표 {1} ms" -f $tpot, $model.targets.tpotMillis)
}

Write-Step "동시성별 처리량 · 포화점 탐색"
$rows = @()
foreach ($c in $cfg.test.concurrency) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $jobs = 1..$c | ForEach-Object {
        Start-ThreadJob -ScriptBlock {
            param($url, $m, $p, $t)
            $body = @{ model = $m; max_tokens = $t; temperature = 0
                messages = @(@{ role = 'user'; content = $p }) } | ConvertTo-Json -Depth 6
            $r = Invoke-WebRequest -Uri ($url + '/v1/chat/completions') -Method POST `
                -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 300 -SkipHttpErrorCheck
            if ($r.StatusCode -ne 200) { return 0 }
            ($r.Content | ConvertFrom-Json).usage.completion_tokens
        } -ArgumentList $BaseUrl, $model.modelId, $prompt, $MaxTokens
    }
    $tokens = ($jobs | Receive-Job -Wait -AutoRemoveJob | Measure-Object -Sum).Sum
    $sw.Stop()
    $sec = $sw.Elapsed.TotalSeconds
    $tps = if ($sec -gt 0) { $tokens / $sec } else { 0 }
    $avgMs = if ($c -gt 0) { $sw.Elapsed.TotalMilliseconds / $c } else { 0 }
    Write-Host ("    동시 {0,3}  ·  {1,6:N1} s  ·  {2,7:N0} tokens  ·  {3,7:N1} tokens/s  ·  요청당 {4,7:N0} ms" -f `
        $c, $sec, $tokens, $tps, $avgMs)
    $rows += [pscustomobject]@{ concurrency = $c; seconds = [math]::Round($sec, 2); tokens = $tokens
        tokensPerSec = [math]::Round($tps, 1); avgMsPerRequest = [math]::Round($avgMs, 0) }
}

$best = ($rows | Sort-Object tokensPerSec -Descending | Select-Object -First 1)
Add-R 'G-P-03 처리량 측정' ([bool]$best) `
    $(if ($best) { ("최대 {0:N1} tokens/s @ 동시 {1}" -f $best.tokensPerSec, $best.concurrency) } else { '측정 실패' })
Add-R 'G-P-04 포화점 기록' ([bool]$best) `
    $(if ($best) { ("HPA 임계값의 근거로 사용 — 동시 " + $best.concurrency) } else { '-' })

$out = "$PSScriptRoot\reports"
New-Item -ItemType Directory -Force $out | Out-Null
$rows | ConvertTo-Json -Depth 4 | Out-File (Join-Path $out ("perf_detail_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".json")) -Encoding utf8

$ok = New-GlmReport -Kind 'perf' -Results $results
Write-Info '결과를 06 §3 의 목표와 대조해 판정하세요.'
if (-not $ok) { exit 1 }
