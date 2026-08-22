<#  GLM 10 전제조건 — 도구·쿼터·라이선스·제원 확인
    실행: pwsh -File .\10_prereq.ps1

    GPU 쿼터가 가장 큰 관문이다. 승인에 수 시간~수 일이 걸리므로 가장 먼저 확인한다.
#>
[CmdletBinding()]
param([string]$ConfigPath = "$PSScriptRoot\..\env.glm.json")

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$model = Get-GlmModel
$results = @()
function Add-R { param($n, $ok, $d) $script:results += [ordered]@{ Name = $n; Status = $(if ($ok) { 'Pass' } else { 'Fail' }); Detail = $d } }

Write-Step "도구 확인"
foreach ($tool in @('az', 'kubectl', 'python')) {
    $found = [bool](Get-Command $tool -ErrorAction SilentlyContinue)
    Add-R ("도구: " + $tool) $found $(if ($found) { '설치됨' } else { '설치 필요' })
}

Write-Step "Azure 로그인·구독"
$acct = az account show -o json 2>$null | ConvertFrom-Json
Add-R 'Azure 로그인' ([bool]$acct) $(if ($acct) { $acct.name } else { 'az login 필요' })

Write-Step "설정 자리표시자 확인"
$placeholders = @(
    @{ n = 'acrName'; v = $cfg.azure.acrName },
    @{ n = 'model.source.repo'; v = $model.source.repo },
    @{ n = 'model.source.revision'; v = $model.source.revision },
    @{ n = 'serving.engineVersion'; v = $model.serving.engineVersion }
)
foreach ($p in $placeholders) {
    $ok = $p.v -and ($p.v -notmatch '<.*교체.*>')
    Add-R ("설정: " + $p.n) $ok $(if ($ok) { $p.v } else { '자리표시자를 실제 값으로 교체하세요' })
}

Write-Step "모델 라이선스·제원 확인"
Add-R '라이선스 확인함(licenseChecked)' ($model.source.licenseChecked -eq $true) `
    '모델 카드의 LICENSE 를 읽고 상업적 사용 가능 여부를 확인한 뒤 true 로 바꾸세요'
Add-R '상업적 사용 허용(commercialUseAllowed)' ($model.source.commercialUseAllowed -eq $true) `
    ("현재 값: " + $model.source.commercialUseAllowed)
Add-R 'vLLM 아키텍처 지원 확인' ($model.serving.engineSupportsArchitecture -eq $true) `
    '지원되지 않으면 기동 자체가 실패합니다 — 릴리스 노트를 확인하세요'

$archKeys = @('totalParamsB', 'numLayers', 'numKeyValueHeads', 'headDim', 'maxContextTokens')
$missing = @($archKeys | Where-Object { $null -eq $model.architecture.$_ })
Add-R '모델 제원 입력 완료' ($missing.Count -eq 0) `
    $(if ($missing.Count -eq 0) { '5개 항목 확인됨' } else { ('미입력: ' + ($missing -join ', ')) })

Write-Step "GPU 쿼터 확인"
$sku = $cfg.azure.gpu.sku
$loc = $cfg.azure.location
$usage = az vm list-usage --location $loc -o json 2>$null | ConvertFrom-Json
if ($usage) {
    # SKU 이름에서 제품군을 추정한다 (예: Standard_NC24ads_A100_v4 → NCADSA100v4)
    $family = ($usage | Where-Object { $_.localName -match 'NC|ND|NV' })
    $lines = $family | ForEach-Object { "{0}={1}/{2}" -f $_.localName, $_.currentValue, $_.limit }
    $anyQuota = [bool]($family | Where-Object { $_.limit -gt 0 })
    Add-R 'GPU 쿼터 존재' $anyQuota $(if ($anyQuota) { '확인됨 — 아래 상세 참조' } else { '모든 GPU 제품군 쿼터가 0 입니다. Portal 에서 증가 요청하세요.' })
    Write-Info "GPU 제품군 쿼터:"
    $family | Sort-Object localName | ForEach-Object {
        Write-Host ("    {0,-45} {1,6} / {2,-6}" -f $_.localName, $_.currentValue, $_.limit)
    }
} else {
    Add-R 'GPU 쿼터 조회' $false '쿼터 조회 실패 — az login 상태를 확인하세요'
}

Write-Step "SKU 지역 가용성"
$skuJson = az vm list-skus --location $loc --resource-type virtualMachines -o json 2>$null | ConvertFrom-Json
if ($skuJson) {
    $target = $skuJson | Where-Object { $_.name -eq $sku }
    $restricted = $target -and $target.restrictions -and $target.restrictions.Count -gt 0
    Add-R ("SKU 사용 가능: " + $sku) ([bool]$target -and -not $restricted) `
        $(if (-not $target) { '이 리전에 없음' } elseif ($restricted) { '구독에 제한이 걸려 있음' } else { '사용 가능' })
} else {
    Add-R 'SKU 조회' $false 'SKU 조회 실패'
}

Write-Step "손익분기 검토 여부"
Add-R '비용 목표 설정(costPerMillionTokensUsd)' ($null -ne $model.targets.costPerMillionTokensUsd) `
    '먼저 목표를 정하고 측정하세요 — 정하지 않으면 판정할 수 없습니다 (06 §5)'

$ok = New-GlmReport -Kind 'prereq' -Results $results
if (-not $ok) {
    Write-Err2 '전제조건 미충족 — 위 [FAIL] 을 해결한 뒤 20_config.ps1 을 실행하세요.'
    exit 1
}
Write-Ok '전제조건 확인 완료 — 다음: .\20_config.ps1'
