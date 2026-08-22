# F2 - Blob Storage 실습 재현 스크립트
# 이니셜: lkm / 리전: koreacentral / 신규 리소스 그룹: rg-advdev-lkm-data (네트워크 실습(rg-advdev-lkm)과 분리)
# 계정 키/연결 문자열은 사용하지 않음 (--auth-mode login 사용)

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 1) 리소스 그룹 생성 (데이터 실습 전용, Part E 네트워크 리소스 그룹과 분리)
az group create --name rg-advdev-lkm-data --location koreacentral

# 2) 스토리지 계정 이름 후보 3개 생성 및 사용 가능 여부 확인
#    (실제 실행 시 매번 다른 난수가 나올 수 있음 — 아래는 이번 실습에서 사용한 예시)
$candidates = @()
for ($i=0; $i -lt 3; $i++) {
  $rand = -join ((0..9) | Get-Random -Count 4)
  $candidates += "stadvdevlkm$rand"
}
foreach ($name in $candidates) {
  az storage account check-name --name $name -o json
}
# 이번 실습에서 확정한 이름: stadvdevlkm6305 (3개 후보 모두 사용 가능 → 첫 번째 후보 채택)

# 3) 스토리지 계정 생성 (Standard_ZRS = 영역 중복 저장, blob 암호화 서비스 활성화)
az storage account create `
  --name stadvdevlkm6305 `
  --resource-group rg-advdev-lkm-data `
  --location koreacentral `
  --sku Standard_ZRS `
  --encryption-services blob

# 4) 컨테이너 생성 (키 없이 Azure AD 로그인 인증으로 생성 — 관리 평면 작업)
az storage container create --account-name stadvdevlkm6305 --name lab-images --auth-mode login

# 4-1) [환경 이슈] 컨테이너 생성(관리 평면)은 구독 Owner 권한으로 되지만,
#      Blob 업로드(데이터 평면)는 별도의 데이터 평면 RBAC 역할이 필요해 아래 역할 부여가 필요했음.
#      본인 계정에 "Storage Blob Data Contributor" 역할을 이 스토리지 계정 범위로만 부여:
$myUpn = az account show --query user.name -o tsv
$storageId = az storage account show --name stadvdevlkm6305 --resource-group rg-advdev-lkm-data --query id -o tsv
az role assignment create --assignee $myUpn --role "Storage Blob Data Contributor" --scope $storageId

# 5) 테스트 파일 업로드 (upload-test.txt: 현재 시각 + 이니셜 기록된 파일)
az storage blob upload `
  --account-name stadvdevlkm6305 `
  --container-name lab-images `
  --name upload-test.txt `
  --file "C:\dev\workspace-igm\advanced-cloud-developer\실습산출물\1차시\upload-test.txt" `
  --auth-mode login `
  --overwrite

# 6) 업로드 결과 확인
az storage blob list --account-name stadvdevlkm6305 --container-name lab-images --auth-mode login --output table

# 7) [제안만 함 — 실행하지 않음] Blob 단위 액세스 계층 변경 명령
# az storage blob set-tier --account-name stadvdevlkm6305 --container-name lab-images --name upload-test.txt --tier Cool --auth-mode login
# az storage blob set-tier --account-name stadvdevlkm6305 --container-name lab-images --name upload-test.txt --tier Archive --auth-mode login

# --- 주의: 이 스토리지 계정(stadvdevlkm6305)은 다음 실습(Azure Files)에서 재사용하므로 삭제하지 말 것 ---
