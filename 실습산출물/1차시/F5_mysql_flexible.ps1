# F5 - Azure Database for MySQL 유연 서버 실습 재현 스크립트
# 이니셜: lkm / 리전: koreacentral / 리소스 그룹: rg-advdev-lkm-data (6-2에서 만든 그룹 재사용)
# 관리자 암호는 포함하지 않음 — 실행 시 본인이 직접 --admin-password 값을 입력할 것

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 0) 사전 확인: 리소스 그룹 존재 여부, 내 공용 IP, 동일 이름 서버 중복 여부
az group exists --name rg-advdev-lkm-data
Invoke-RestMethod -Uri "https://api.ipify.org"   # 이번 실습에서 확인된 값: 59.11.126.89
az mysql flexible-server list --resource-group rg-advdev-lkm-data --query "[].name" -o tsv

# 1) 서버 생성 (관리자 암호는 본인이 직접 입력 — 아래 <ADMIN_PASSWORD> 자리)
#    [환경 이슈] --version 8.0은 더 이상 허용되지 않음. 허용값: 5.7 / 8.0.21 / 8.4 / 9.5
#    강의자료의 "8.0" 계열에 맞춰 8.0.21로 조정.
#    [환경 이슈] 최소 스토리지는 강의자료의 10GiB가 아니라 20GiB로 상향되어 20으로 조정.
az mysql flexible-server create `
  --name mysql-advdev-lkm `
  --resource-group rg-advdev-lkm-data `
  --location koreacentral `
  --admin-user mysqladmin `
  --admin-password "<ADMIN_PASSWORD>" `
  --sku-name Standard_B1ms `
  --tier Burstable `
  --storage-size 20 `
  --version 8.0.21 `
  --backup-retention 7 `
  --high-availability Disabled `
  --public-access 59.11.126.89 `
  --yes

# 1-1) [환경 이슈] 서버 생성은 State: Ready로 성공했으나,
#      생성 명령 마지막 단계(방화벽 규칙 자동 설정)에서 (InternalServerError)가 발생하며 방화벽 규칙이 비어있는 상태로 남았음.
#      CLI로 재시도(az mysql flexible-server firewall-rule create)도 4회 연속 동일 오류가 발생해,
#      포털 [mysql-advdev-lkm] -> [네트워킹] -> [규칙 추가]에서 AllowMyIP(59.11.126.89~59.11.126.89) 규칙을 직접 추가함.

# 2) 서버 상태 확인
az mysql flexible-server show `
  --resource-group rg-advdev-lkm-data `
  --name mysql-advdev-lkm `
  --query "{name:name, state:state, version:version, sku:sku.name, tier:sku.tier, storageGB:storage.storageSizeGb, backupDays:backup.backupRetentionDays, ha:highAvailability.mode, network:network.publicNetworkAccess, fqdn:fullyQualifiedDomainName}" `
  -o table

# 3) 방화벽 규칙 확인 (0.0.0.0/0 없는지 검증)
az mysql flexible-server firewall-rule list --resource-group rg-advdev-lkm-data --name mysql-advdev-lkm -o table

# 4) 연결 방법 (실제 접속은 본인이 직접 수행 — 암호는 대화형 입력)
#    로컬에 mysql 클라이언트가 설치되어 있어야 함
# mysql -h mysql-advdev-lkm.mysql.database.azure.com -u mysqladmin -p

# 5) [설명만] 포털에서 데이터베이스(labdb) 만들기
#    포털 [mysql-advdev-lkm] -> [설정] -> [데이터베이스] -> [+ 추가] -> 이름 labdb -> [저장]
#    이후 [데이터베이스] 목록에서 labdb 존재 확인

# --- 주의: 실습 후 반드시 리소스 그룹(rg-advdev-lkm-data)을 삭제할 것 (Blob/Files 실습에서 재사용한 스토리지 계정도 함께 정리됨을 인지) ---
