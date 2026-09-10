# 공통 함수 — 모든 스크립트가 점 소싱(dot-source)해서 쓴다.
#
#   . "$PSScriptRoot\lib.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────── 출력

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 66) -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host ('=' * 66) -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host "▶ $Text" -ForegroundColor White
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  ✓ $Text" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Text)
    Write-Host "  ⚠ $Text" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  ✗ $Text" -ForegroundColor Red
}

# ─────────────────────────────────────────── 검사 결과 수집
#
# 검증 스크립트가 «몇 개 통과 / 몇 개 실패»를 파일로 남긴다.
# prd 승격 조건이 «stg 검증 fail = 0» 이므로, 사람의 기억이 아니라 파일이 근거가 된다.

$script:Results = @()

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [string]$Detail = ''
    )
    $script:Results += [pscustomobject]@{
        id     = $Id
        name   = $Name
        passed = $Passed
        detail = $Detail
    }
    if ($Passed) { Write-Ok "[$Id] $Name" }
    else         { Write-Fail "[$Id] $Name — $Detail" }
}

function Save-Results {
    param(
        [Parameter(Mandatory)][string]$Env,
        [Parameter(Mandatory)][string]$OutDir
    )
    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    $pass = @($script:Results | Where-Object { $_.passed }).Count
    $fail = @($script:Results | Where-Object { -not $_.passed }).Count

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path  = Join-Path $OutDir "${Env}_verify_$stamp.json"

    $payload = [pscustomobject]@{
        environment = $Env
        timestamp   = (Get-Date).ToString('o')
        pass        = $pass
        fail        = $fail
        checks      = $script:Results
    }
    $payload | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding utf8

    Write-Host ''
    Write-Host ('-' * 66)
    if ($fail -eq 0) {
        Write-Host " 결과: 통과 $pass 건 · 실패 0건" -ForegroundColor Green
    } else {
        Write-Host " 결과: 통과 $pass 건 · 실패 $fail 건" -ForegroundColor Red
    }
    Write-Host " 기록: $path"
    return $fail
}

# ─────────────────────────────────────────── 전제 확인

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ToolVersion {
    param([Parameter(Mandatory)][string]$Name, [string[]]$VersionArgs = @('--version'))
    try {
        $out = & $Name @VersionArgs 2>&1 | Select-Object -First 1
        return "$out".Trim()
    } catch {
        return $null
    }
}

# ─────────────────────────────────────────── 확인 프롬프트
#
# ⚠️ 파괴적인 작업은 반드시 사람이 «yes» 를 입력해야 진행한다.
#    -Force 플래그 하나로 넘어가게 만들면 언젠가 실수로 눌린다.

function Confirm-Destructive {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Target
    )
    Write-Host ''
    Write-Host '⚠️  되돌릴 수 없는 작업입니다.' -ForegroundColor Yellow
    Write-Host "    작업: $Action"
    Write-Host "    대상: $Target"
    Write-Host ''
    $answer = Read-Host "계속하려면 정확히 'yes' 를 입력하세요"
    if ($answer -ne 'yes') {
        Write-Host '취소했습니다.' -ForegroundColor Yellow
        return $false
    }
    return $true
}

# ─────────────────────────────────────────── Terraform 실행

function Invoke-Terraform {
    param(
        [Parameter(Mandatory)][string]$EnvDir,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    Push-Location $EnvDir
    try {
        Write-Host "  terraform $($Arguments -join ' ')" -ForegroundColor DarkGray
        & terraform @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "terraform $($Arguments -join ' ') 가 실패했습니다 (종료 코드 $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
}

function Get-EnvDir {
    param([Parameter(Mandatory)][string]$Env)
    $dir = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'terraform') "envs$([IO.Path]::DirectorySeparatorChar)$Env"
    if (-not (Test-Path $dir)) {
        throw "환경 폴더를 찾을 수 없습니다: $dir"
    }
    return $dir
}
