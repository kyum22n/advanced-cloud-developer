<#  GLM 50 스모크 — 기능 테스트 G-F-01~08 (06 §2) #>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\..\env.glm.json",
    [string]$BaseUrl = 'http://localhost:8000'
)

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$model = Get-GlmModel
$results = @()
function Add-R { param($n, $ok, $d) $script:results += [ordered]@{ Name = $n; Status = $(if ($ok) { 'Pass' } else { 'Fail' }); Detail = $d } }

Write-Step "전제 — 포트포워딩 확인"
Write-Info ("대상: " + $BaseUrl)
Write-Info ("필요 시: kubectl port-forward -n {0} svc/{1} 8000:8000" -f $cfg.k8s.namespace, $cfg.k8s.appName)

function Invoke-Glm {
    param([string]$Path, [string]$Method = 'GET', $Body = $null, [int]$TimeoutSec = 120)
    $params = @{ Uri = ($BaseUrl + $Path); Method = $Method; TimeoutSec = $TimeoutSec; SkipHttpErrorCheck = $true }
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 6)
        $params.ContentType = 'application/json; charset=utf-8'
    }
    try { Invoke-WebRequest @params } catch { $null }
}

Write-Step "G-F-01 모델 등록 확인"
$r = Invoke-Glm -Path '/v1/models'
$modelsOk = $r -and $r.StatusCode -eq 200 -and $r.Content -match [regex]::Escape($model.modelId)
Add-R 'G-F-01 /v1/models' $modelsOk $(if ($r) { "HTTP " + $r.StatusCode } else { '응답 없음' })

Write-Step "G-F-02 기본 생성"
$body = @{ model = $model.modelId; max_tokens = 64
    messages = @(@{ role = 'user'; content = '한 문장으로 자기소개해줘.' }) }
$r = Invoke-Glm -Path '/v1/chat/completions' -Method 'POST' -Body $body
$genOk = $false; $detail = '응답 없음'
if ($r -and $r.StatusCode -eq 200) {
    $j = $r.Content | ConvertFrom-Json
    $text = $j.choices[0].message.content
    $genOk = -not [string]::IsNullOrWhiteSpace($text)
    $detail = "HTTP 200 · 길이 " + ($text | Measure-Object -Character).Characters
} elseif ($r) { $detail = "HTTP " + $r.StatusCode }
Add-R 'G-F-02 기본 생성' $genOk $detail

Write-Step "G-F-05 컨텍스트 초과 처리"
$long = '가' * 200000
$body = @{ model = $model.modelId; max_tokens = 16; messages = @(@{ role = 'user'; content = $long }) }
$r = Invoke-Glm -Path '/v1/chat/completions' -Method 'POST' -Body $body
# 400 계열이면 정상 — 프로세스가 죽지 않고 오류를 돌려주는 것이 핵심이다
$ctxOk = $r -and $r.StatusCode -ge 400 -and $r.StatusCode -lt 500
Add-R 'G-F-05 컨텍스트 초과 시 4xx' $ctxOk $(if ($r) { "HTTP " + $r.StatusCode } else { '응답 없음(프로세스 종료 의심)' })

Write-Step "G-F-07 잘못된 모델명"
$body = @{ model = 'no-such-model-xyz'; max_tokens = 8; messages = @(@{ role = 'user'; content = 'hi' }) }
$r = Invoke-Glm -Path '/v1/chat/completions' -Method 'POST' -Body $body
$badOk = $r -and $r.StatusCode -ge 400 -and $r.StatusCode -lt 500
Add-R 'G-F-07 잘못된 모델명 4xx' $badOk $(if ($r) { "HTTP " + $r.StatusCode } else { '응답 없음' })

Write-Step "G-F-08 생존 확인 (전체 테스트 후에도 살아 있는가)"
$r = Invoke-Glm -Path '/health'
Add-R 'G-F-08 /health 생존' ($r -and $r.StatusCode -eq 200) $(if ($r) { "HTTP " + $r.StatusCode } else { '응답 없음' })

$ok = New-GlmReport -Kind 'smoke' -Results $results
if (-not $ok) { Write-Err2 '기능 테스트 실패 — 계약·설정을 확인하세요.'; exit 1 }
Write-Ok '기능 테스트 통과 — 다음: .\60_perf.ps1'
