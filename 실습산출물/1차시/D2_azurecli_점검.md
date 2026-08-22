# Azure CLI 설치 및 실습 준비 상태 점검

## 요약

| 항목 | 내용 |
|---|---|
| 설치 여부 | 신규 설치 (winget) |
| 설치 버전 | azure-cli 2.89.0 (azure-cli-core 2.89.0, azure-cli-telemetry 1.1.0) |
| 로그인 계정 | kyumni207@o.shinhan.ac.kr |
| 테넌트 | 신한대학교 (tenantDefaultDomain: o.shinhan.ac.kr, tenantId: `***4a80`) |
| 선택 구독 | Azure in Open (subscriptionId: `***8807`) — 접근 가능한 구독이 1개뿐이라 별도 선택 없이 기본값 사용 |
| 구독 상태 | Enabled / isDefault: true |
| 리전(koreacentral) | 사용 가능 — `Korea Central / koreacentral / (Asia Pacific) Korea Central` |

## 리소스 공급자 등록 상태

| 리소스 공급자 | 최초 조회 | 조치 | 최종 상태 |
|---|---|---|---|
| Microsoft.Network | NotRegistered | 사용자 확인 후 등록 실행 | Registered |
| Microsoft.Compute | NotRegistered | 사용자 확인 후 등록 실행 | Registered |
| Microsoft.Storage | NotRegistered | 사용자 확인 후 등록 실행 | Registered |
| Microsoft.DBforMySQL | NotRegistered | 사용자 확인 후 등록 실행 | Registered |
| Microsoft.OperationalInsights | NotRegistered | 사용자 확인 후 등록 실행 | Registered |

## 검증 (인수조건)

| 조건 | 결과 | 비고 |
|---|---|---|
| (a) `az version` 정상 | O | 2.89.0, 새 세션(PATH 갱신 후) 기준으로도 정상 동작 |
| (b) `az account show`가 구독 정보 반환 | O | 구독명 "Azure in Open", 상태 Enabled, isDefault true |
| (c) koreacentral 사용 가능 | O | `az account list-locations` 결과에 포함 |
| (d) 5개 공급자 상태 모두 Registered 또는 등록 방법 안내 | O | 사용자 확인 후 5개 모두 등록 실행 → 전부 Registered로 확인 |

X 항목 없음.

## 진행 로그

1. `az version` 실행 → 미설치 확인.
2. `winget install -e --id Microsoft.AzureCLI` 실행 → 2.89.0 설치 성공 (msi 수동 설치 불필요, winget이 PATH 자동 등록).
3. 세션 PATH 갱신 후 `az version` 재확인 → 정상 (임의 폴더 `C:\`에서도 확인).
4. `az login` 실행 → 브라우저 계정 선택 창에서 1차 시도는 사용자 취소로 실패, 재시도하여 로그인 성공.
5. `az account show`로 활성 구독 확인, `az account list --output table`로 전체 목록 확인 → 접근 가능한 구독 1개(Azure in Open)뿐이라 구독 선택 절차는 생략.
6. `az account list-locations --output table`에서 koreacentral 사용 가능 확인.
7. 5개 리소스 공급자 등록 상태 조회 → 전부 NotRegistered.
8. 등록 실행 여부를 사용자에게 확인받은 후 `az provider register -n <이름>`을 5개 모두 실행 (리소스 생성/삭제 없음, 공급자 등록만 수행).
9. 등록 완료까지 상태를 폴링(`az provider show -n <이름> --query registrationState`)하여 5개 모두 Registered 확인.

## 참고 (보안)
- 구독 ID/테넌트 ID는 화면 조회 시에는 전체 값을 사용했으며, 본 문서에는 마지막 4자리만 남기고 마스킹하여 저장했습니다.
- 이 점검 과정에서 리소스 생성·삭제 명령은 실행하지 않았습니다(조회 및 공급자 등록만 수행).
