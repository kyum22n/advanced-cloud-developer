<#
.SYNOPSIS
    전제 조건 확인 — 아무것도 만들지 않는다.

.DESCRIPTION
    구축을 시작하기 «전»에 필요한 것이 모두 준비됐는지 확인한다.
    도구가 없거나 권한이 모자란 상태로 시작하면 절반쯤 만들어진 인프라가 남는다.

.PARAMETER Env
    dev | stg | prd

.EXAMPLE
    .\10_prereq.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'stg', 'prd')][string]$Env
)

. "$PSScriptRoot\lib.ps1"

Write-Head "전제 조건 확인 — $Env"

# ── 도구
Write-Step '필수 도구'

$tools = @(
    @{ Name = 'terraform'; Args = @('version'); Min = '1.9' }
    @{ Name = 'az';        Args = @('version'); Min = '2.60' }
)

foreach ($t in $tools) {
    if (-not (Test-Command $t.Name)) {
        Add-Check "T-$($t.Name)" "$($t.Name) 설치됨" $false '설치되어 있지 않습니다'
        continue
    }
    $v = Get-ToolVersion $t.Name $t.Args
    Add-Check "T-$($t.Name)" "$($t.Name) — $v" $true
}

# ⚠️ Terraform 버전은 «있다»가 아니라 «충분하다»를 봐야 한다.
#    azurerm 4.x 프로바이더는 Terraform 1.9 이상을 요구한다.
if (Test-Command 'terraform') {
    $raw = (& terraform version -json 2>$null) | ConvertFrom-Json
    $ver = [version]($raw.terraform_version)
    $ok  = $ver -ge [version]'1.9.0'
    Add-Check 'T-tfver' "Terraform 1.9 이상 (현재 $ver)" $ok `
        'azurerm 4.x 프로바이더는 Terraform 1.9 이상이 필요합니다'
}

# ── Azure 로그인
Write-Step 'Azure 인증'

$account = $null
try {
    $account = (& az account show -o json 2>$null) | ConvertFrom-Json
} catch { }

if ($null -eq $account) {
    Add-Check 'A-login' 'Azure 로그인' $false "az login 을 먼저 실행하세요"
} else {
    Add-Check 'A-login' "Azure 로그인 — $($account.user.name)" $true
    Add-Check 'A-sub'   "구독 — $($account.name)" $true "id=$($account.id)"

    # prd 는 구독을 잘못 고르면 큰일이므로 한 번 더 보여 준다.
    if ($Env -eq 'prd') {
        Write-Warn2 "운영 환경입니다. 구독이 «$($account.name)» 가 맞습니까?"
    }
}

# ── 리소스 공급자 등록
Write-Step '리소스 공급자 등록 상태'

$providers = @(
    'Microsoft.AppPlatform'      # Azure Spring Apps
    'Microsoft.ServiceBus'
    'Microsoft.EventHub'
    'Microsoft.DocumentDB'       # Cosmos DB
    'Microsoft.Cache'            # Redis
    'Microsoft.Storage'
    'Microsoft.KeyVault'
    'Microsoft.ContainerRegistry'
    'Microsoft.OperationalInsights'
    'Microsoft.Insights'
    'Microsoft.Network'
)

if ($null -ne $account) {
    foreach ($p in $providers) {
        $state = & az provider show --namespace $p --query registrationState -o tsv 2>$null
        $ok = ($state -eq 'Registered')
        Add-Check "P-$p" "$p" $ok "현재 상태: $state · az provider register --namespace $p"
    }
}

# ── 상태 저장소
Write-Step 'Terraform 상태 저장소'

$backendFile = Join-Path (Get-EnvDir $Env) 'backend.tf'
if (Test-Path $backendFile) {
    $backend = Get-Content $backendFile -Raw
    $sa = [regex]::Match($backend, 'storage_account_name\s*=\s*"([^"]+)"').Groups[1].Value
    if ($sa -and $null -ne $account) {
        $exists = & az storage account show --name $sa -o none 2>$null; $found = ($LASTEXITCODE -eq 0)
        Add-Check 'S-state' "상태 저장소 계정 $sa" $found `
            'shared/bootstrap 를 먼저 적용하세요'
    }
}

# ── tfvars
Write-Step '변수 파일'

$envDir  = Get-EnvDir $Env
$tfvars  = Join-Path $envDir 'terraform.tfvars'
$example = Join-Path $envDir 'terraform.tfvars.example'

if (Test-Path $tfvars) {
    Add-Check 'V-tfvars' 'terraform.tfvars 존재' $true

    # ⚠️ 예제 파일의 자리표시자를 그대로 두고 적용하면 엉뚱한 구독에 배포된다.
    $content = Get-Content $tfvars -Raw
    $hasPlaceholder = $content -match '00000000-0000-0000-0000-000000000000'
    Add-Check 'V-subid' '구독 ID 가 실제 값으로 채워짐' (-not $hasPlaceholder) `
        '자리표시자(00000000-…)가 남아 있습니다'
} else {
    Add-Check 'V-tfvars' 'terraform.tfvars 존재' $false `
        "$example 를 복사해 terraform.tfvars 로 만들고 값을 채우세요"
}

# ── prd 승격 조건
if ($Env -eq 'prd') {
    Write-Step '운영 승격 조건'

    $verifyDir = Join-Path $PSScriptRoot '..\검증결과'
    $stgResults = @()
    if (Test-Path $verifyDir) {
        $stgResults = @(Get-ChildItem $verifyDir -Filter 'stg_verify_*.json' -ErrorAction SilentlyContinue)
    }

    if ($stgResults.Count -eq 0) {
        Add-Check 'R-stg' 'stg 검증 통과 기록' $false `
            'stg 에서 80_verify.ps1 을 먼저 실행하세요'
    } else {
        $latest = $stgResults | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $result = Get-Content $latest.FullName -Raw | ConvertFrom-Json
        Add-Check 'R-stg' "stg 검증 통과 (실패 $($result.fail)건)" ($result.fail -eq 0) `
            "$($latest.Name) 에 실패 $($result.fail)건이 기록되어 있습니다"
    }
}

$failCount = Save-Results -Env "${Env}_prereq" -OutDir (Join-Path $PSScriptRoot '..\검증결과')

Write-Host ''
if ($failCount -eq 0) {
    Write-Host '다음: .\20_validate.ps1 -Env ' -NoNewline; Write-Host $Env -ForegroundColor Cyan
} else {
    Write-Host '위 실패 항목을 해결한 뒤 다시 실행하세요.' -ForegroundColor Yellow
}
exit $failCount
