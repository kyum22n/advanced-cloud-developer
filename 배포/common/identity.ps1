<#  공통 아이덴티티 모듈 — Managed Identity / Workload Identity 적용·검증 함수
    사용: . "$PSScriptRoot\..\common\identity.ps1"   (lib.ps1 을 먼저 점 소싱할 것)

    설계 원칙 (설계\공통\07_아이덴티티·시크릿_설계서.md 와 1:1 대응)
      1) 비밀을 '만들지 않는 것' > '잘 보관하는 것'
      2) 플랫폼이 주체를 증명한다 — 코드가 자격 증명을 들고 다니지 않는다
      3) 권한은 리소스 단위 최소 범위로 부여한다
      4) 적용했다면 반드시 검증한다 (Test-* 함수)

    az CLI 2.60.0 기준으로 실제 존재를 확인한 명령만 사용합니다.
#>

# ─────────────────────────────────────────────────────────────
# 조회
# ─────────────────────────────────────────────────────────────
function Get-AzTenantId {
    az account show --query tenantId -o tsv
}

function Get-AksOidcIssuer {
    param([Parameter(Mandatory)][string]$ResourceGroup, [Parameter(Mandatory)][string]$Name)
    az aks show -g $ResourceGroup -n $Name --query oidcIssuerProfile.issuerUrl -o tsv 2>$null
}

function Get-FederatedSubject {
    param([Parameter(Mandatory)][string]$Namespace, [Parameter(Mandatory)][string]$ServiceAccount)
    # 워크로드 ID 의 subject 는 반드시 이 형식이어야 한다 — 오타 한 글자면 토큰 교환이 실패한다
    "system:serviceaccount:{0}:{1}" -f $Namespace, $ServiceAccount
}

# ─────────────────────────────────────────────────────────────
# 적용 (모두 멱등 — 이미 있으면 재사용)
# ─────────────────────────────────────────────────────────────
function New-UserAssignedIdentity {
    <# 사용자 할당 관리 ID 를 만들고 clientId/principalId 를 돌려준다. #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Location
    )
    az identity show -g $ResourceGroup -n $Name -o none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Checked -What ("managed identity: " + $Name) -Script {
            az identity create -g $ResourceGroup -n $Name -l $Location -o none
        }
    } else {
        Write-Info ("관리 ID 재사용: " + $Name)
    }
    [pscustomobject]@{
        name        = $Name
        clientId    = (az identity show -g $ResourceGroup -n $Name --query clientId -o tsv)
        principalId = (az identity show -g $ResourceGroup -n $Name --query principalId -o tsv)
        id          = (az identity show -g $ResourceGroup -n $Name --query id -o tsv)
    }
}

function Grant-AzRole {
    <# 최소 범위(Scope) 로 역할을 부여한다. 이미 있으면 조용히 통과한다. #>
    param(
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Scope
    )
    $existing = az role assignment list --assignee $PrincipalId --scope $Scope --query "[?roleDefinitionName=='$Role'] | length(@)" -o tsv 2>$null
    if ($existing -and [int]$existing -gt 0) { Write-Info ("역할 이미 부여됨: " + $Role); return $true }
    az role assignment create --assignee-object-id $PrincipalId --assignee-principal-type ServicePrincipal `
        --role $Role --scope $Scope -o none 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok ("역할 부여: " + $Role); return $true }
    Write-Warn2 ("역할 부여 실패(권한 부족 가능): " + $Role)
    return $false
}

function New-FederatedCredential {
    <# ServiceAccount ↔ 관리 ID 를 OIDC 로 연합한다. 이것이 '비밀번호 없는 접근'의 핵심. #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$IdentityName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Issuer,
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter(Mandatory)][string]$ServiceAccount
    )
    $subject = Get-FederatedSubject -Namespace $Namespace -ServiceAccount $ServiceAccount
    az identity federated-credential show -g $ResourceGroup --identity-name $IdentityName -n $Name -o none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Info ("연합 자격 증명 재사용: " + $Name)
    } else {
        Invoke-Checked -What ("federated credential: " + $Name) -Script {
            az identity federated-credential create -g $ResourceGroup --identity-name $IdentityName -n $Name `
                --issuer $Issuer --subject $subject --audiences api://AzureADTokenExchange -o none
        }
    }
    $subject
}

function Enable-PostgresEntraAuth {
    <# PostgreSQL 유연한 서버에 Entra ID 인증을 켜고 관리 ID 를 Entra 관리자로 등록한다.
       → 앱이 '비밀번호' 대신 '토큰'으로 접속할 수 있게 된다. #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$DisplayName,
        [ValidateSet('Enabled','Disabled')][string]$PasswordAuth = 'Enabled'
    )
    Invoke-Checked -What 'postgres Entra 인증 활성화' -Script {
        az postgres flexible-server update -g $ResourceGroup -n $Server `
            --active-directory-auth Enabled --password-auth $PasswordAuth -o none
    }
    $adminExists = az postgres flexible-server ad-admin list -g $ResourceGroup -s $Server --query "[?objectId=='$PrincipalId'] | length(@)" -o tsv 2>$null
    if ($adminExists -and [int]$adminExists -gt 0) {
        Write-Info "Entra DB 관리자 이미 등록됨"
    } else {
        az postgres flexible-server ad-admin create -g $ResourceGroup -s $Server `
            --display-name $DisplayName --object-id $PrincipalId --type ServicePrincipal -o none 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Ok ("Entra DB 관리자 등록: " + $DisplayName) }
        else { Write-Warn2 "Entra DB 관리자 등록 실패 — 구독 권한/전파 지연 가능(재실행하면 해결되는 경우가 많음)" }
    }
}

function Grant-RedisDataAccess {
    <# Redis 를 액세스 키가 아니라 Entra 주체로 접근하도록 액세스 정책을 할당한다. #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$Cache,
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Alias,
        [string]$Policy = 'Data Contributor'
    )
    $name = ('apa-' + $Alias)
    az redis access-policy-assignment show -g $ResourceGroup -n $Cache --policy-assignment-name $name -o none 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Info "Redis 액세스 정책 이미 할당됨"; return }
    az redis access-policy-assignment create -g $ResourceGroup -n $Cache `
        --policy-assignment-name $name --access-policy-name $Policy `
        --object-id $PrincipalId --object-id-alias $Alias -o none 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok ("Redis Entra 액세스 정책 할당: " + $Policy) }
    else { Write-Warn2 "Redis 액세스 정책 할당 실패 — 캐시 계층/지역이 Entra 인증을 지원하는지 확인" }
}

# ─────────────────────────────────────────────────────────────
# 검증 — '적용했다'가 아니라 '작동한다'를 확인한다
# ─────────────────────────────────────────────────────────────
function Test-IdentityPosture {
    <# 아이덴티티 태세를 점검해 [ordered]@{Name;Status;Detail} 배열을 돌려준다.
       80_verify.ps1 이 이 결과를 그대로 리포트에 합친다. #>
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$AksName,
        [Parameter(Mandatory)][string]$IdentityName,
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter(Mandatory)][string]$ServiceAccount,
        [string]$KeyVaultName,
        [string]$PostgresName,
        [string]$StorageAccount,
        [string]$RedisName,
        [string]$AcrName
    )
    $r = @()
    function _add($n, $ok, $d) { $script:__r += [ordered]@{ Name=$n; Status=$(if($ok){'Pass'}else{'Fail'}); Detail=$d } }
    $script:__r = @()

    # ① 클러스터 측 — 토큰을 발급할 수 있는가
    $oidcOn = az aks show -g $ResourceGroup -n $AksName --query oidcIssuerProfile.enabled -o tsv 2>$null
    _add 'AKS OIDC 발급자 사용' ($oidcOn -eq 'true') ("oidcIssuerEnabled=" + $oidcOn)

    $wiOn = az aks show -g $ResourceGroup -n $AksName --query securityProfile.workloadIdentity.enabled -o tsv 2>$null
    _add 'AKS 워크로드 ID 애드온 사용' ($wiOn -eq 'true') ("workloadIdentityEnabled=" + $wiOn)

    $kvAddon = az aks show -g $ResourceGroup -n $AksName --query "addonProfiles.azureKeyvaultSecretsProvider.enabled" -o tsv 2>$null
    _add 'Key Vault 시크릿 공급자 애드온 사용' ($kvAddon -eq 'true') ("csiSecretsProvider=" + $kvAddon)

    # ② 연합 — 이 ServiceAccount 가 이 관리 ID 로 교환될 수 있는가
    $issuer = Get-AksOidcIssuer -ResourceGroup $ResourceGroup -Name $AksName
    $subjectExpected = Get-FederatedSubject -Namespace $Namespace -ServiceAccount $ServiceAccount
    $fcJson = az identity federated-credential list -g $ResourceGroup --identity-name $IdentityName -o json 2>$null | ConvertFrom-Json
    $fcMatch = $false
    if ($fcJson) {
        foreach ($fc in $fcJson) {
            if ($fc.subject -eq $subjectExpected -and $fc.issuer -eq $issuer) { $fcMatch = $true }
        }
    }
    _add '연합 자격 증명이 발급자·subject 와 일치' $fcMatch ("subject=" + $subjectExpected)

    # ③ 클러스터 안 — ServiceAccount 주석이 실제 clientId 인가
    $clientId = az identity show -g $ResourceGroup -n $IdentityName --query clientId -o tsv 2>$null
    $saClient = kubectl get sa $ServiceAccount -n $Namespace -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>$null
    _add 'ServiceAccount 주석 = 관리 ID clientId' ($clientId -and $saClient -eq $clientId) ("sa=" + $saClient)

    # ④ 파드 안 — 토큰이 실제로 주입되었는가 (웹훅이 동작했다는 증거)
    $pod = kubectl get pods -n $Namespace -l app=myapp -o jsonpath='{.items[0].metadata.name}' 2>$null
    $tokenOk = $false; $tokenDetail = 'pod 없음'
    if ($pod) {
        $envClient = kubectl exec $pod -n $Namespace -- printenv AZURE_CLIENT_ID 2>$null
        $tokenPath = kubectl exec $pod -n $Namespace -- printenv AZURE_FEDERATED_TOKEN_FILE 2>$null
        $tokenOk = [bool]$envClient -and [bool]$tokenPath
        $tokenDetail = ("AZURE_CLIENT_ID=" + $(if($envClient){'주입됨'}else{'없음'}) + " tokenFile=" + $(if($tokenPath){'주입됨'}else{'없음'}))
    }
    _add '파드에 워크로드 ID 토큰 주입' $tokenOk $tokenDetail

    # ⑤ 데이터 계층 — 비밀번호 없이 접근할 준비가 되었는가
    if ($PostgresName) {
        $adAuth = az postgres flexible-server show -g $ResourceGroup -n $PostgresName --query authConfig.activeDirectoryAuth -o tsv 2>$null
        _add 'PostgreSQL Entra ID 인증 사용' ($adAuth -eq 'Enabled' -or $adAuth -eq 'enabled') ("activeDirectoryAuth=" + $adAuth)

        $principalId = az identity show -g $ResourceGroup -n $IdentityName --query principalId -o tsv 2>$null
        $adminCnt = az postgres flexible-server ad-admin list -g $ResourceGroup -s $PostgresName --query "[?objectId=='$principalId'] | length(@)" -o tsv 2>$null
        _add '관리 ID 가 PostgreSQL Entra 관리자' ([int]($adminCnt -as [int]) -ge 1) ("matched=" + $adminCnt)
    }
    if ($StorageAccount) {
        $shared = az storage account show -g $ResourceGroup -n $StorageAccount --query allowSharedKeyAccess -o tsv 2>$null
        _add 'Storage 공유 키 액세스 차단' ($shared -eq 'false' -or $shared -eq 'False') ("allowSharedKeyAccess=" + $shared)
    }
    if ($RedisName) {
        $apa = az redis access-policy-assignment list -g $ResourceGroup -n $RedisName --query "length(@)" -o tsv 2>$null
        _add 'Redis Entra 액세스 정책 할당' ([int]($apa -as [int]) -ge 1) ("assignments=" + $apa)
    }

    # ⑥ 권한 최소성 — 구독 범위 소유자/기여자 같은 과대 권한이 없는가
    $principalId2 = az identity show -g $ResourceGroup -n $IdentityName --query principalId -o tsv 2>$null
    $wide = az role assignment list --assignee $principalId2 --query "[?scope=='/subscriptions/'+'$((az account show --query id -o tsv))'] | length(@)" -o tsv 2>$null
    _add '관리 ID 에 구독 범위 광역 권한 없음' ([int]($wide -as [int]) -eq 0) ("subscriptionScopeAssignments=" + $wide)

    return $script:__r
}

function Write-IdentitySummary {
    <# 검증 결과를 사람이 읽을 수 있게 요약한다. #>
    param([Parameter(Mandatory)]$Results)
    $pass = ($Results | Where-Object { $_.Status -eq 'Pass' }).Count
    $fail = ($Results | Where-Object { $_.Status -ne 'Pass' }).Count
    Write-Host ""
    Write-Host ("  아이덴티티 태세: Pass {0} / Fail {1}" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
    foreach ($x in $Results) {
        $mark = if ($x.Status -eq 'Pass') { '  [OK]  ' } else { '  [FAIL]' }
        $color = if ($x.Status -eq 'Pass') { 'Green' } else { 'Red' }
        Write-Host ("{0} {1} — {2}" -f $mark, $x.Name, $x.Detail) -ForegroundColor $color
    }
}
