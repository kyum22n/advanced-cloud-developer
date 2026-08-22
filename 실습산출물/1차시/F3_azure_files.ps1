# F3 - Azure Files 실습 재현 스크립트 (6-2에서 만든 스토리지 계정 재사용)
# 이니셜: lkm / 리전: koreacentral / 리소스 그룹: rg-advdev-lkm-data / 재사용 계정: stadvdevlkm6305
# 계정 키/연결 문자열은 사용하지 않음 (--auth-mode login 사용)

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 1) 재사용할 스토리지 계정 확인 (신규 생성 없음)
az storage account list --resource-group rg-advdev-lkm-data --output table
# → stadvdevlkm6305 확인

# 2) 파일 공유 생성 (할당량 5GB)
az storage share-rm create --resource-group rg-advdev-lkm-data --storage-account stadvdevlkm6305 --name lab-share --quota 5

# 2-1) [환경 이슈] Azure Files 데이터 평면(OAuth) 작업에는 --enable-file-backup-request-intent 플래그가 필요하고,
#      Blob과 별개로 "Storage File Data Privileged Contributor" 역할이 추가로 필요했음.
#      본인 계정에 이 스토리지 계정 범위로만 역할 부여:
$myUpn = az account show --query user.name -o tsv
$storageId = az storage account show --name stadvdevlkm6305 --resource-group rg-advdev-lkm-data --query id -o tsv
az role assignment create --assignee $myUpn --role "Storage File Data Privileged Contributor" --scope $storageId

# 3) 테스트 파일 업로드 (share-test.txt: 현재 시각 + 이니셜 기록)
az storage file upload `
  --account-name stadvdevlkm6305 `
  --share-name lab-share `
  --source "C:\dev\workspace-igm\advanced-cloud-developer\실습산출물\1차시\share-test.txt" `
  --path share-test.txt `
  --auth-mode login `
  --enable-file-backup-request-intent

# 4) 업로드 결과 확인
az storage file list --account-name stadvdevlkm6305 --share-name lab-share --auth-mode login --enable-file-backup-request-intent --output table

# 5) [설명만, 실제 마운트는 하지 않음]
#    포털 [스토리지 계정: stadvdevlkm6305] -> [파일 공유] -> lab-share -> [연결] 클릭 시
#    PowerShell용 net use 스크립트가 자동 생성됨 (예: net use Z: \\stadvdevlkm6305.file.core.windows.net\lab-share ...)
#    이 방식은 SMB(445번 포트)로 통신하므로 사내/사용자 네트워크에서 445번 아웃바운드가 막혀 있으면 연결이 실패함.

# 6) 같은 계정 안 컨테이너 + 파일 공유 공존 증명
az storage container list --account-name stadvdevlkm6305 --auth-mode login --output table
az storage share-rm list --storage-account stadvdevlkm6305 --resource-group rg-advdev-lkm-data --output table

# --- 주의: stadvdevlkm6305 계정은 계속 재사용 중이므로 삭제하지 말 것 (Part E 5-7과 별개, rg-advdev-lkm-data 정리 시 별도 확인 필요) ---
