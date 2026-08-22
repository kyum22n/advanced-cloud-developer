# E6 - NAT Gateway 실습 재현 스크립트 (5-5 환경 재사용)
# 이니셜: lkm / 리전: koreacentral / 기존 리소스 그룹: rg-advdev-lkm / 기존 VNet: vnet-advdev, subnet-1

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 사전 확인: 리소스 그룹·subnet-1 존재 및 기존 natGateway 설정(변경 전) 확인
az group exists --name rg-advdev-lkm
az network vnet subnet show --resource-group rg-advdev-lkm --vnet-name vnet-advdev --name subnet-1 --query "{name:name, natGateway:natGateway}" -o json

# 1) NAT용 공용 IP 생성 (Standard SKU, 시간당 과금)
az network public-ip create --resource-group rg-advdev-lkm --name pip-nat --sku Standard --location koreacentral --zone 1

# 2) NAT 게이트웨이 생성 (유휴 시간 제한 10분, 시간당 과금)
az network nat gateway create --resource-group rg-advdev-lkm --name natgw-advdev --public-ip-addresses pip-nat --idle-timeout 10 --location koreacentral

# 3) subnet-1에 NAT 게이트웨이 연결 (변경 전/후 비교)
az network vnet subnet show --resource-group rg-advdev-lkm --vnet-name vnet-advdev --name subnet-1 --query "{name:name, natGateway:natGateway}" -o json
az network vnet subnet update --resource-group rg-advdev-lkm --vnet-name vnet-advdev --name subnet-1 --nat-gateway natgw-advdev
az network vnet subnet show --resource-group rg-advdev-lkm --vnet-name vnet-advdev --name subnet-1 --query "{name:name, natGateway:natGateway}" -o json

# 4) pip-nat 실제 공용 IP 주소 확인
az network public-ip show --resource-group rg-advdev-lkm --name pip-nat --query ipAddress -o tsv

# 5) 포털: [가상 머신] -> [vm-1] -> [연결] -> [Bastion] -> azureuser 로그인 -> [연결]

# 6) vm-1 bash에서 아웃바운드 IP 확인 (수동 실행)
#    curl ifconfig.me
#    → 4)의 pip-nat 주소와 일치하는지 확인

# --- 실습 종료 후 반드시 정리 (Part E 5-7, rg-advdev-lkm 전체 삭제 시 자동 포함) ---
# az resource list --resource-group rg-advdev-lkm --output table
# az group delete --name rg-advdev-lkm --yes --no-wait
# az group exists --name rg-advdev-lkm
