# VNet + Bastion + VM 2대 실습 결과

이니셜: `lkm` / 리전: `koreacentral` / 리소스 그룹: `rg-advdev-lkm`

## 1. 생성된 리소스 목록

| 이름 | 종류 | 상태 |
|---|---|---|
| vnet-advdev | Microsoft.Network/virtualNetworks | Succeeded |
| pip-bastion | Microsoft.Network/publicIPAddresses (Standard) | Succeeded |
| bastion-advdev | Microsoft.Network/bastionHosts | Succeeded |
| vm-1NSG | Microsoft.Network/networkSecurityGroups | Succeeded |
| vm-1VMNic | Microsoft.Network/networkInterfaces | Succeeded |
| vm-1 | Microsoft.Compute/virtualMachines | Succeeded |
| vm-1_disk1_... | Microsoft.Compute/disks | Succeeded |
| vm-2NSG | Microsoft.Network/networkSecurityGroups | Succeeded |
| vm-2VMNic | Microsoft.Network/networkInterfaces | Succeeded |
| vm-2 | Microsoft.Compute/virtualMachines | Succeeded |
| vm-2_disk1_... | Microsoft.Compute/disks | Succeeded |

서브넷은 리소스 목록에 별도로 나오지 않지만(VNet의 하위 속성), `az network vnet subnet list`로 `subnet-1`(10.0.0.0/24)과 `AzureBastionSubnet`(10.0.1.0/26) 2개가 vnet-advdev 안에 존재함을 확인했습니다.

## 2. VM 사설 IP

| VM | 사설 IP | 공용 IP |
|---|---|---|
| vm-1 | 10.0.0.4 | 없음 |
| vm-2 | 10.0.0.5 | 없음 |

`az vm list-ip-addresses` 결과에 공용 IP 컬럼 자체가 나타나지 않아, 두 VM 모두 공용 IP가 없는 것으로 확인됩니다.

## 3. Bastion 접속 및 ping 결과

| 단계 | 결과 |
|---|---|
| 포털에서 [vm-1] → [연결] → [Bastion] 탭 → azureuser 로그인 | **성공** |
| vm-1 bash에서 `ping -c 4 10.0.0.5` 실행 | **성공** (0% packet loss) |

## 4. 소요 시간 메모

| 단계 | 비고 |
|---|---|
| 리소스 그룹 · VNet · 서브넷 생성 | 수 초 내 즉시 완료 |
| Bastion 배포 | 1차 시도는 `bastion` CLI 확장 미설치로 대화형 프롬프트에서 실패 → 확장 설치 후 재시도, 약 10분 내 `Succeeded` |
| VM 2대 생성 | PowerShell 5.1에서 `--public-ip-address ""` 빈 문자열 인자가 누락되는 버그로 1차 시도 실패 → `--public-ip-address '""'` 형태로 재실행 후 성공 |

## 5. 검증 (인수조건)

| 조건 | 결과 | 비고 |
|---|---|---|
| (a) 리소스 그룹에 VNet·2개 서브넷·공용 IP·Bastion·VM 2대 모두 존재 | O | 1절 리소스 목록 + 서브넷 2개 확인 |
| (b) vm-1, vm-2에 공용 IP가 없음 | O | 2절 참고 |
| (c) Bastion으로 vm-1 접속 성공 | O | 3절 참고 |
| (d) vm-1 → vm-2 ping 응답 수신 | O | 3절 참고 — 0% packet loss |

4개 항목 모두 **O**로, 실패 항목이 없어 별도 원인 진단은 없습니다. (참고: 진행 중 겪었던 2건의 실행 오류 — bastion 확장 미설치, PowerShell 빈 문자열 인자 버그 — 는 모두 도구·환경 이슈였고 재시도로 해결되었으며, 최종 리소스 상태에는 영향이 없습니다.)

---

**⚠️ 이 리소스는 시간당 과금됩니다. 5-7의 정리 단계를 반드시 수행하세요.**
