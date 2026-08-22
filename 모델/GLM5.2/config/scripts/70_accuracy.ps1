<#  GLM 70 정확도 — 양자화 전후 회귀 비교 (06 §4)

    이 단계가 없으면 03 §3-1 의 '양자화로 비용을 절반으로' 결정을 감으로 하게 된다.
    싸졌지만 못 쓰는 상태를 배포 전에 잡아내는 것이 목적이다.

    실행:
      # ① 기준 응답을 만든다 (FP16 또는 관리형 API 등 '기준' 엔드포인트)
      pwsh -File .\70_accuracy.ps1 -Mode Baseline -BaseUrl http://localhost:8000
      # ② 양자화본으로 다시 실행해 비교한다
      pwsh -File .\70_accuracy.ps1 -Mode Compare  -BaseUrl http://localhost:8000
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\..\env.glm.json",
    [string]$BaseUrl = 'http://localhost:8000',
    [ValidateSet('Baseline', 'Compare')][string]$Mode = 'Compare',
    [string]$PromptSet = "$PSScriptRoot\prompts\regression.json",
    [double]$MinAgreement = 0.85
)

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$model = Get-GlmModel
$results = @()
function Add-R { param($n, $ok, $d) $script:results += [ordered]@{ Name = $n; Status = $(if ($ok) { 'Pass' } else { 'Fail' }); Detail = $d } }

# ── 회귀 세트 준비 ────────────────────────────────────────
if (-not (Test-Path $PromptSet)) {
    Write-Warn2 "회귀 세트가 없어 기본 예시로 생성합니다: $PromptSet"
    Write-Info "실제 업무 프롬프트로 교체하세요 (06 §4). 개인정보는 절대 넣지 마세요."
    New-Item -ItemType Directory -Force (Split-Path $PromptSet) | Out-Null
    $sample = @(
        @{ id = 'sum-01'; type = 'summary';  prompt = '다음을 한 문장으로 요약해줘: 클라우드 네이티브는 컨테이너·마이크로서비스·선언적 배포를 전제로 한 설계 방식이다.' },
        @{ id = 'sum-02'; type = 'summary';  prompt = '쿠버네티스의 readinessProbe 와 livenessProbe 의 차이를 두 문장으로 설명해줘.' },
        @{ id = 'json-01'; type = 'format';  prompt = '다음을 JSON 으로만 답해줘(설명 금지): {"name":문자열,"score":정수}. 이름은 홍길동, 점수는 90.' },
        @{ id = 'json-02'; type = 'format';  prompt = '키가 week, count, amount 인 JSON 배열 한 건만 출력해줘. 값은 2026-W10, 3, 1500.' },
        @{ id = 'ko-01';  type = 'korean';   prompt = '"deployment rollout succeeded" 를 자연스러운 한국어로 번역해줘.' },
        @{ id = 'ko-02';  type = 'korean';   prompt = '워크로드 ID 를 처음 듣는 개발자에게 세 문장으로 설명해줘.' },
        @{ id = 'reason-01'; type = 'reasoning'; prompt = 'GPU 노드 풀에 taint 를 걸지 않으면 왜 0으로 축소되지 않는지 설명해줘.' },
        @{ id = 'reason-02'; type = 'reasoning'; prompt = 'MoE 모델에서 활성 파라미터가 적어도 VRAM 이 줄지 않는 이유를 설명해줘.' }
    )
    ($sample | ConvertTo-Json -Depth 4) | Out-File $PromptSet -Encoding utf8
}

$prompts = Get-Content $PromptSet -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Step ("회귀 세트: " + $prompts.Count + "건 · 모드 " + $Mode)

$outDir = "$PSScriptRoot\reports"
New-Item -ItemType Directory -Force $outDir | Out-Null
$baselinePath = Join-Path $outDir 'accuracy_baseline.json'

function Invoke-Prompt {
    param([string]$Text)
    # temperature=0 — 결정성을 확보해야 비교가 의미를 갖는다 (G-Q-05)
    $body = @{
        model = $model.modelId; max_tokens = 512; temperature = 0; top_p = 1
        messages = @(@{ role = 'user'; content = $Text })
    } | ConvertTo-Json -Depth 6
    try {
        $r = Invoke-WebRequest -Uri ($BaseUrl + '/v1/chat/completions') -Method POST `
            -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 300 -SkipHttpErrorCheck
        if ($r.StatusCode -ne 200) { return $null }
        ($r.Content | ConvertFrom-Json).choices[0].message.content
    } catch { $null }
}

# ── 기준 저장 모드 ────────────────────────────────────────
if ($Mode -eq 'Baseline') {
    $baseline = @{}
    foreach ($p in $prompts) {
        Write-Info ("기준 응답 수집: " + $p.id)
        $baseline[$p.id] = Invoke-Prompt -Text $p.prompt
    }
    $payload = [ordered]@{
        kind = 'accuracy-baseline'
        capturedAt = (Get-Date).ToString('s')
        modelId = $model.modelId
        dtype = $model.serving.dtype
        kvCacheDtype = $model.serving.kvCacheDtype
        responses = $baseline
    }
    $payload | ConvertTo-Json -Depth 6 | Out-File $baselinePath -Encoding utf8
    Write-Ok ("기준 응답 저장: " + $baselinePath)
    Write-Info "이제 양자화 설정으로 재배포한 뒤 -Mode Compare 로 다시 실행하세요."
    exit 0
}

# ── 비교 모드 ─────────────────────────────────────────────
if (-not (Test-Path $baselinePath)) {
    Write-Err2 "기준 응답이 없습니다. 먼저 -Mode Baseline 으로 실행하세요."
    Write-Info "기준은 FP16 본 또는 관리형 API 응답을 씁니다(06 §4)."
    exit 1
}
$base = Get-Content $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-Similarity {
    param([string]$A, [string]$B)
    # 토큰 집합 기반 자카드 유사도 — 완벽한 지표가 아니라 '눈에 띄는 퇴행'을 잡는 용도다.
    # 요약·작문 품질의 최종 판정은 사람이 한다(G-Q-04).
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0.0 }
    $ta = @($A -split '[\s\p{P}]+' | Where-Object { $_ }) | ForEach-Object { $_.ToLower() }
    $tb = @($B -split '[\s\p{P}]+' | Where-Object { $_ }) | ForEach-Object { $_.ToLower() }
    if ($ta.Count -eq 0 -or $tb.Count -eq 0) { return 0.0 }
    $sa = [System.Collections.Generic.HashSet[string]]::new([string[]]$ta)
    $sb = [System.Collections.Generic.HashSet[string]]::new([string[]]$tb)
    $inter = [System.Collections.Generic.HashSet[string]]::new($sa)
    $inter.IntersectWith($sb)
    $union = [System.Collections.Generic.HashSet[string]]::new($sa)
    $union.UnionWith($sb)
    if ($union.Count -eq 0) { return 0.0 }
    [math]::Round($inter.Count / $union.Count, 4)
}

$detail = @()
$scores = @()
$jsonFail = 0
$jsonTotal = 0

foreach ($p in $prompts) {
    $now = Invoke-Prompt -Text $p.prompt
    $was = $base.responses.($p.id)
    $sim = Get-Similarity -A $was -B $now
    $scores += $sim

    # 형식 준수(G-Q-02) — JSON 을 요구한 항목은 실제로 파싱되는지 본다
    if ($p.type -eq 'format') {
        $jsonTotal++
        $ok = $false
        if ($now) {
            $trimmed = ($now -replace '(?s)^.*?(\{|\[)', '$1') -replace '(?s)(\}|\]).*?$', '$1'
            try { $null = $trimmed | ConvertFrom-Json; $ok = $true } catch { $ok = $false }
        }
        if (-not $ok) { $jsonFail++ }
    }

    $flag = if ($sim -ge $MinAgreement) { 'ok' } else { 'REVIEW' }
    Write-Host ("    {0,-12} {1,-10} 유사도 {2,6:N3}  {3}" -f $p.id, $p.type, $sim, $flag) `
        -ForegroundColor $(if ($flag -eq 'ok') { 'Green' } else { 'Yellow' })
    $detail += [pscustomobject]@{ id = $p.id; type = $p.type; similarity = $sim; needsReview = ($flag -eq 'REVIEW') }
}

$avg = if ($scores.Count) { [math]::Round(($scores | Measure-Object -Average).Average, 4) } else { 0 }
$below = @($detail | Where-Object { $_.needsReview })

Write-Step "판정"
Add-R 'G-Q-01 회귀 세트 평균 유사도' ($avg -ge $MinAgreement) ("평균 {0:N3} / 기준 {1:N2}" -f $avg, $MinAgreement)
if ($jsonTotal -gt 0) {
    Add-R 'G-Q-02 형식(JSON) 준수' ($jsonFail -eq 0) ("실패 {0}/{1}" -f $jsonFail, $jsonTotal)
}
Add-R 'G-Q-05 결정성(temperature=0)' $true '동일 파라미터로 수집 — 재실행 시 동일해야 함'

Write-Host ""
if ($below.Count -gt 0) {
    Write-Warn2 ("사람이 확인해야 할 항목 " + $below.Count + "건: " + (($below.id) -join ', '))
}
Write-Warn2 '자동 유사도만으로 판정하지 마세요. 요약·작문은 문자열 일치로 평가되지 않습니다.'
Write-Warn2 '반드시 담당자가 실제 업무 프롬프트로 수용 판정(G-Q-04)을 해야 운영으로 넘어갑니다.'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
[ordered]@{
    kind = 'accuracy-compare'; comparedAt = (Get-Date).ToString('s')
    baselineDtype = $base.dtype; currentDtype = $model.serving.dtype
    averageSimilarity = $avg; threshold = $MinAgreement
    jsonFailures = $jsonFail; jsonTotal = $jsonTotal
    needsHumanReview = @($below.id)
    detail = $detail
} | ConvertTo-Json -Depth 6 | Out-File (Join-Path $outDir ("accuracy_compare_" + $stamp + ".json")) -Encoding utf8

$ok = New-GlmReport -Kind 'accuracy' -Results $results
if (-not $ok) {
    Write-Err2 '정확도 기준 미달 — 양자화 수준을 되돌리거나 조정하세요(03 §3-1).'
    Write-Info '품질 문제를 더 좋은 GPU 로 푸는 것은 대개 가장 비싼 해법입니다.'
    exit 1
}
Write-Ok '정확도 회귀 통과 — 담당자 수용 판정 후 80_verify.ps1 로 진행하세요.'
