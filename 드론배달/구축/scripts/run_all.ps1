<#
.SYNOPSIS
    구축 절차 안내 — ⛔ 자동으로 실행하지 않는다.

.DESCRIPTION
    각 단계를 순서대로 «보여 준다». 실제 실행은 사람이 한 단계씩 한다.

    왜 자동 실행하지 않는가
      · 30_plan 의 결과를 «사람이 읽는 것»이 이 절차의 핵심이다.
      · 자동화하면 그 검토가 사라지고, 데이터 저장소가 조용히 재생성될 수 있다.
      · 파괴적 작업에 대한 확인 프롬프트도 의미를 잃는다.

    -DryRun 없이 실행하면 «검증까지만» 자동으로 하고 apply 앞에서 멈춘다.

.EXAMPLE
    .\run_all.ps1 -Env dev
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'stg', 'prd')][string]$Env,
    [switch]$RunChecks
)

. "$PSScriptRoot\lib.ps1"

Write-Head "드론 배달 인프라 구축 — $Env"

$steps = @(
    @{ N = '10'; Script = '10_prereq.ps1';   Desc = '전제 조건 확인';      Safe = $true  }
    @{ N = '20'; Script = '20_validate.ps1'; Desc = '정적 검증';           Safe = $true  }
    @{ N = '30'; Script = '30_plan.ps1';     Desc = '실행 계획 생성';      Safe = $true  }
    @{ N = '40'; Script = '40_apply.ps1';    Desc = '인프라 적용';         Safe = $false }
    @{ N = '80'; Script = '80_verify.ps1';   Desc = '배포 검증';           Safe = $true  }
    @{ N = '90'; Script = '90_cleanup.ps1';  Desc = '리소스 정리 (선택)';  Safe = $false }
)

Write-Host ''
Write-Host ' 단계'
foreach ($s in $steps) {
    $mark = if ($s.Safe) { '읽기·검증' } else { '⚠ 변경' }
    Write-Host ("   {0}  {1,-18} {2,-16} .\{3} -Env {4}" -f $s.N, $s.Desc, $mark, $s.Script, $Env)
}

Write-Host ''
Write-Host ('-' * 66)

if (-not $RunChecks) {
    Write-Host ''
    Write-Host ' 위 순서대로 «한 단계씩» 실행하세요.'
    Write-Host ' 검증 단계(10·20)만 자동으로 돌리려면: -RunChecks'
    Write-Host ''
    Write-Host ' ⛔ 40_apply 와 90_cleanup 은 이 스크립트가 실행하지 않습니다.'
    Write-Host '    계획을 사람이 읽는 것이 이 절차의 핵심이기 때문입니다.'
    exit 0
}

# ── 안전한 단계만 자동 실행
foreach ($s in $steps | Where-Object { $_.Safe -and $_.N -in @('10', '20') }) {
    Write-Head "$($s.N). $($s.Desc)"
    & (Join-Path $PSScriptRoot $s.Script) -Env $Env
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Fail "$($s.Desc) 에서 실패했습니다. 여기서 멈춥니다."
        exit $LASTEXITCODE
    }
}

Write-Host ''
Write-Host ('=' * 66) -ForegroundColor Green
Write-Host ' 검증 단계를 통과했습니다.' -ForegroundColor Green
Write-Host ('=' * 66) -ForegroundColor Green
Write-Host ''
Write-Host ' 다음은 사람이 직접 실행하세요:'
Write-Host "   .\30_plan.ps1  -Env $Env    ← 계획을 «읽고» 확인"
Write-Host "   .\40_apply.ps1 -Env $Env    ← 확인 후에만"
exit 0
