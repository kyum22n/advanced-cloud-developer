<#  GLM 30 빌드 — vLLM 이미지를 ACR 에서 빌드한다 (가중치는 포함하지 않는다) #>
[CmdletBinding()]
param([string]$ConfigPath = "$PSScriptRoot\..\env.glm.json")

. "$PSScriptRoot\lib.ps1"
$cfg = Get-GlmConfig -Path $ConfigPath
$model = Get-GlmModel
$acr = $cfg.azure.acrName
$version = $model.serving.engineVersion

if (-not $version -or $version -match '<.*>') { throw "model.json 의 serving.engineVersion 을 고정 버전으로 교체하세요 (latest 금지)." }

Write-Step "vLLM 이미지 빌드 (ACR 클라우드 빌드)"
$tag = "glm-" + (Get-Date -Format 'yyyyMMddHHmm')
$ctx = (Resolve-Path "$PSScriptRoot\..").Path

# 베이스 이미지 버전을 치환한 임시 Dockerfile 을 만든다
$dockerfile = Join-Path $ctx 'Dockerfile'
$tmp = Join-Path $ctx 'Dockerfile.build'
(Get-Content $dockerfile -Raw -Encoding UTF8).Replace('VLLM_VERSION_PLACEHOLDER', $version) |
    Out-File $tmp -Encoding utf8 -NoNewline

try {
    Invoke-Checked -What ("az acr build (" + $tag + ")") -Script {
        az acr build -r $acr -t ("glm:" + $tag) -f $tmp $ctx --only-show-errors -o none
    }
} finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

$loginServer = az acr show -n $acr --query loginServer -o tsv
$build = [ordered]@{
    registry = $acr; loginServer = $loginServer; repository = 'glm'; tag = $tag
    vllmVersion = $version; builtAt = (Get-Date).ToString('s')
}
New-Item -ItemType Directory -Force "$PSScriptRoot\reports" | Out-Null
$build | ConvertTo-Json | Out-File "$PSScriptRoot\reports\last-build.json" -Encoding utf8

Write-Ok ("이미지: " + $loginServer + "/glm:" + $tag)
Write-Info "다음: .\40_deploy.ps1"
