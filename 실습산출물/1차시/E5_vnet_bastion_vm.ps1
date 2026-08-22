# E5 - VNet + Bastion + VM 2대 실습 재현 스크립트
# 이니셜: lkm / 리전: koreacentral
# 관리자 암호는 스크립트에 포함되어 있지 않습니다 — az vm create 실행 시 대화형으로 직접 입력하세요.

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 1) 리소스 그룹
az group create --name rg-advdev-lkm --location koreacentral

# 2) VNet + subnet-1
az network vnet create --resource-group rg-advdev-lkm --name vnet-advdev `
  --address-prefix 10.0.0.0/16 --subnet-name subnet-1 --subnet-prefixes 10.0.0.0/24 `
  --location koreacentral

# 3) AzureBastionSubnet (이름 고정, 최소 /26 필요)
az network vnet subnet create --resource-group rg-advdev-lkm --vnet-name vnet-advdev `
  --name AzureBastionSubnet --address-prefix 10.0.1.0/26

# 4) Bastion용 공용 IP (Standard SKU, 시간당 과금)
az network public-ip create --resource-group rg-advdev-lkm --name pip-bastion `
  --sku Standard --location koreacentral --zone 1 2 3

# 4-1) bastion CLI 확장이 없으면 먼저 설치 (대화형 프롬프트 방지를 위해 --yes 사용)
az extension add --name bastion --yes

# 5) Bastion 호스트 생성 (배포 약 10분, 시간당 과금)
az network bastion create --resource-group rg-advdev-lkm --name bastion-advdev `
  --public-ip-address pip-bastion --vnet-name vnet-advdev --location koreacentral

# 6) VM 2대 생성 (공용 IP 없음, 관리자 계정 azureuser / 인증 방식 password)
#    주의: Windows PowerShell 5.1에서 빈 문자열("") 인자가 native 실행파일 호출 시 누락되는
#    알려진 버그가 있어, --public-ip-address 값은 '""' (작은따옴표로 큰따옴표 두 개 감싸기)로 전달합니다.
#    암호는 실행 시 프롬프트에서 직접 입력 (이 스크립트에는 포함하지 않음)
az vm create --resource-group rg-advdev-lkm --name vm-1 --image Ubuntu2204 `
  --admin-username azureuser --authentication-type password `
  --vnet-name vnet-advdev --subnet subnet-1 --public-ip-address '""' `
  --location koreacentral

az vm create --resource-group rg-advdev-lkm --name vm-2 --image Ubuntu2204 `
  --admin-username azureuser --authentication-type password `
  --vnet-name vnet-advdev --subnet subnet-1 --public-ip-address '""' `
  --location koreacentral

# 7) 생성된 리소스 확인
az resource list --resource-group rg-advdev-lkm --output table

# 사설 IP 확인 (공용 IP 컬럼이 비어 있으면 공용 IP 없음 확인)
az vm list-ip-addresses --resource-group rg-advdev-lkm --output table

# 8) 포털에서 Bastion 접속: [가상 머신] 검색 -> [vm-1] -> [연결] -> [Bastion] 탭
#    -> 사용자 이름 azureuser / 암호 입력 -> [연결]

# 9) vm-1의 bash에서 vm-2 사설 IP로 ping (수동 실행)
#    ping -c 4 10.0.0.5

# --- 실습 종료 후 반드시 정리 (Part E 5-7) ---
# az resource list --resource-group rg-advdev-lkm --output table   # 삭제 대상 재확인
# az group delete --name rg-advdev-lkm --yes --no-wait
# az group exists --name rg-advdev-lkm                              # false 확인될 때까지 대기
