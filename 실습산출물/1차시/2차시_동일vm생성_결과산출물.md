# 2차시 — vm-edu-cc 동일 스펙 VM 생성 결과 산출물

작성일: 2026-08-07

## 1. 작업 목적

기존 Azure VM **vm-edu-cc**(리소스 그룹 `rg-edu-cc-validate`, 지역 koreacentral)와 동일한 스펙의 VM을 새로 생성하고, 로컬 PC의 공인 IP로 RDP 원격 접속이 가능하도록 NSG 규칙을 구성한다.

원본 VM 스펙 명세서: `vm-edu-cc_vm스펙_및_동일생성_가이드`

## 2. 진행 경과

### 2-1. 구독 불일치 확인
- 현재 로그인 계정: `kyumni207@o.shinhan.ac.kr`
- 현재 구독: **Azure in Open** (구독 ID `2097fe45-213d-4678-beb7-65bf83638807`)
- 원본 가이드 문서 기준 구독: Visual Studio Enterprise 구독 – MPN
- 현재 구독에서 원본 리소스 그룹 `rg-edu-cc-validate` 조회 시 `ResourceGroupNotFound` — 원본 VM이 이 구독에 존재하지 않음을 확인
- 사용자 결정: **현재 구독("Azure in Open")으로 그대로 진행**

### 2-2. 1차 생성 (임시 비밀번호 방식) → 되돌림
- 최초 시도에서는 Azure CLI 비대화형 실행을 위해 스크립트가 임의 비밀번호를 생성해 `--admin-password`로 전달함
- 사용자가 "비밀번호는 직접 입력하겠다, 스크립트·로그에 남기지 말라"고 명확히 요청 → 해당 리소스 그룹(`rg-edu-cc-clone`) **전체 삭제로 되돌림** (`az group delete`)

### 2-3. 2차 생성 (비밀번호 사용자 직접 입력 방식)
- 리소스 그룹, VNet, 공용 IP, NSG, NIC까지는 CLI로 사전 구성
- VM 생성 명령(`az vm create`)은 `--admin-password`를 **생략**하여 Azure CLI가 대화형으로 비밀번호를 요청하도록 구성
- 사용자가 자신의 관리자 PowerShell 터미널에서 직접 명령을 실행하고 비밀번호를 입력 (본 세션 로그에 비밀번호 미노출)
- 중간 오류: 사용자가 Claude Code 채팅 전용 접두사 `!`를 실제 PowerShell 콘솔에 그대로 붙여넣어 `!`가 PowerShell의 논리 NOT 연산자로 해석되며 `InvalidLeftHandSide` 파서 오류 발생 → `!` 접두사를 제거하고 재실행하여 해결

## 3. 생성 결과물 (리소스 인벤토리)

| 리소스 | 이름 | 비고 |
|---|---|---|
| 리소스 그룹 | `rg-edu-cc-clone` | koreacentral |
| 가상 네트워크 | `vm-edu-cc-clone-vnet` | 10.0.0.0/16 |
| 서브넷 | `vm-edu-cc-clone-subnet` | 10.0.0.0/24 |
| 공용 IP | `vm-edu-cc-clone-pip` | Standard, 정적, IPv4, 유휴 4분, **20.41.96.129** |
| NSG | `vm-edu-cc-clone-nsg` | RDP(3389) 인바운드 규칙 포함 |
| NIC | `vm-edu-cc-clone-nic` | 가속 네트워킹 사용 안 함, 개인 IP 10.0.0.4(동적) |
| VM | `vm-edu-cc-clone` | 아래 4장 참조 |
| OS 디스크 | `vm-edu-cc-clone-osdisk` | Premium_LRS, 127 GiB |

## 4. 원본 대비 스펙 검증 결과

| 항목 | 원본(vm-edu-cc) | 신규(vm-edu-cc-clone) | 일치 여부 |
|---|---|---|---|
| VM 크기 | Standard_D4s_v5 | Standard_D4s_v5 | ✅ |
| 이미지 SKU | win11-24h2-pro | win11-24h2-pro (latest) | ✅ |
| 보안 유형 | TrustedLaunch | TrustedLaunch | ✅ |
| Secure Boot / vTPM | true / true | true / true | ✅ |
| OS 디스크 | Premium_LRS, 127 GiB, ReadWrite 캐싱, Detach | 동일 | ✅ |
| 데이터 디스크 | 0개 | 0개 | ✅ |
| 관리자 계정 | eduadmin | eduadmin | ✅ |
| 가속 네트워킹 | false | false | ✅ |
| 가용성 영역 | 없음 | 없음 | ✅ |
| 패치 모드 | AutomaticByOS | AutomaticByOS | ✅ |
| 공용 IP 종류 | Standard/정적, 유휴 4분 | Standard/정적, 유휴 4분 | ✅ |
| NSG RDP 규칙 | TCP 3389, 우선순위 1000 | TCP 3389, 우선순위 1000 | ✅ (허용 원본 IP는 로컬 PC 공인 IP로 대체) |

## 5. NSG / 원격 접속 검증

- NSG 규칙 `RDP`: 우선순위 1000, TCP 3389, Allow, 원본 IP **59.11.126.89**
- 검증 시점 로컬 PC 공인 IP: **59.11.126.89** — NSG 규칙과 일치 확인
- RDP 포트 도달 테스트: `Test-NetConnection 20.41.96.129 -Port 3389` → `TcpTestSucceeded = True`
- VM 프로비저닝 상태: `Succeeded`, 전원 상태(검증 당시): `VM running`

## 6. 현재 상태 (2026-08-07 기준)

- VM 전원 상태: **VM deallocated** (컴퓨팅 과금 중지, 사용자 요청으로 할당 취소 수행)
- 유지되는 리소스: OS 디스크(127 GiB Premium SSD), 정적 공용 IP(20.41.96.129), NSG, NIC, VNet 등 VM 설정 전체
- 계속 과금되는 항목: OS 디스크 스토리지 요금, Standard 정적 공용 IP 요금 (컴퓨팅 요금은 발생하지 않음)
- NSG 허용 IP(59.11.126.89)와 로컬 PC 공인 IP 재확인 결과 일치 (최종 확인 시점 기준)

## 7. 실습(2026-08-08, 09:30 시작) 전 해야 할 일

1. **로컬 PC 공인 IP 재확인** — 밤사이 IP가 바뀌었을 수 있으므로 실습 시작 전 반드시 재확인
   - 확인 방법: `curl ifconfig.me` 또는 `(Invoke-RestMethod ifconfig.me/ip)`
2. **IP가 바뀐 경우** — NSG 규칙(`rg-edu-cc-clone` / `vm-edu-cc-clone-nsg` / 규칙명 `RDP`)의 원본 IP를 새 공인 IP로 갱신
   ```
   az network nsg rule update -g rg-edu-cc-clone --nsg-name vm-edu-cc-clone-nsg -n RDP --source-address-prefixes <새IP>
   ```
3. **VM 기동**
   ```
   az vm start -g rg-edu-cc-clone -n vm-edu-cc-clone
   ```
4. **RDP 접속 확인**: `mstsc /v:20.41.96.129` (관리자 계정 `eduadmin`, 생성 시 직접 입력한 비밀번호 사용 — 별도 기록 없음)

> ⚠️ 참고: 자동 예약(내일 09:20 자동 IP 확인/NSG 갱신)은 검토 후 진행하지 않기로 결정함(세션 종료 시 예약이 소멸되는 한계로 인해 사용자가 수동 확인을 선택). 실습 시작 전 위 1~4단계를 수동으로 진행할 것.

## 8. 실습 종료 후 정리 (참고)

리소스 그룹 단위로 삭제해야 OS 디스크(Detach 옵션) 잔여 과금을 막을 수 있음:
```
az group delete -n rg-edu-cc-clone --yes
az group exists -n rg-edu-cc-clone   # false면 정리 완료
```
