<#  prd 롤백 — 직전 리비전으로 즉시 복귀
    실행: pwsh -File .\rollback.ps1 [-ToRevision 3]
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\env.prd.json",
    [int]$ToRevision = 0,
    [switch]$Force
)
. "$PSScriptRoot\..\common\lib.ps1"
$cfg = Get-DeployConfig -Path $ConfigPath
$ns = $cfg.app.namespace

Write-Step "운영 롤백"
kubectl rollout history deploy/$($cfg.app.name) -n $ns
if (-not (Confirm-Destructive -Target "직전(또는 지정) 리비전으로 롤백" -Force:$Force)) { exit 0 }

if ($ToRevision -gt 0) {
    Invoke-Checked -What ("리비전 " + $ToRevision + " 으로 롤백") -Script {
        kubectl rollout undo deploy/$($cfg.app.name) -n $ns --to-revision=$ToRevision
    }
} else {
    Invoke-Checked -What '직전 리비전으로 롤백' -Script { kubectl rollout undo deploy/$($cfg.app.name) -n $ns }
}
Invoke-Checked -What '롤아웃 완료 대기' -Script { kubectl rollout status deploy/$($cfg.app.name) -n $ns --timeout=600s }

$base = $cfg.test.baseUrl
if ($base) {
    Wait-Condition -What '헬스 회복' -TimeoutSec 180 -IntervalSec 5 -Condition { Test-HttpOk -Url ($base + '/healthz') }
    try { (Invoke-WebRequest ($base + '/version') -UseBasicParsing).Content | Write-Host } catch { }
}
Write-Warn2 'GitOps 를 쓰는 경우: Git 의 overlay 태그도 되돌려야 다음 Sync 에서 다시 올라가지 않습니다.'
Write-Ok '롤백 완료'
