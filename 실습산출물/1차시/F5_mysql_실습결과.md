# Azure Database for MySQL 유연 서버 실습 결과

이니셜: `lkm` / 리전: `koreacentral` / 리소스 그룹: `rg-advdev-lkm-data` (6-2에서 만든 그룹 재사용)

## 1. 계획한 사양

| 항목 | 값 |
|---|---|
| 워크로드 | 개발 |
| 계층 | 버스트 가능(Burstable) |
| 크기 | Standard_B1ms |
| 스토리지 | 20 GiB (강의자료 10GiB는 현재 최소 허용값이 아니어서 20GiB로 상향 조정) |
| 백업 보존 | 7일 |
| 고가용성 | 사용 안 함 |
| 가용성 영역 | 기본 설정 없음 |
| 네트워킹 | 공용 액세스 — 내 IP(`59.11.126.89`)만 허용 |
| 버전 | 8.0.21 (`--version 8.0`은 더 이상 허용값이 아니어서 조정, 허용값: 5.7 / 8.0.21 / 8.4 / 9.5) |

사용자 확인 후 위 사양으로 생성을 진행했습니다.

## 2. 생성 과정에서 발생한 오류 및 해결

| 단계 | 오류 | 원인/조치 |
|---|---|---|
| 최초 생성 명령 | `Incorrect value for --version. Allowed values : {'9.5', '8.0.21', '5.7', '8.4'}` | `--version 8.0` → `--version 8.0.21`로 수정 후 재실행 |
| 재실행한 생성 명령 | `(InternalServerError) An unexpected error occured...` | Azure 서비스 측 오류로 판단. `az mysql flexible-server list`로 확인한 결과 **서버 자체는 State: Ready로 정상 생성됨** — 오류는 생성 명령 마지막 단계(방화벽 규칙 자동 설정)에서만 발생한 것으로 확인 |
| `az mysql flexible-server firewall-rule create` (CLI 재시도, 4회) | 매회 동일한 `(InternalServerError)` | 30초 간격 4회 재시도에도 동일 오류 반복되어 CLI 경로를 포기하고, **포털 [네트워킹] 메뉴에서 직접 방화벽 규칙 추가**로 전환하여 해결 |

## 3. 서버 상태 (생성 완료 후 조회 결과)

| 항목 | 값 |
|---|---|
| 이름 | mysql-advdev-lkm |
| 상태(State) | **Ready** |
| 버전 | 8.0.21 |
| SKU | Standard_B1ms |
| 계층 | Burstable |
| 스토리지 | 20 GiB |
| 백업 보존 | 7일 |
| 고가용성 | Disabled |
| 공용 네트워크 액세스 | Enabled |
| FQDN | mysql-advdev-lkm.mysql.database.azure.com |

## 4. 방화벽 규칙

| 이름 | 시작 IP | 끝 IP |
|---|---|---|
| AllowMyIP | 59.11.126.89 | 59.11.126.89 |

규칙은 **1개만 존재**하며, `0.0.0.0/0`(전체 허용) 규칙은 **없음**을 확인했습니다. 이 규칙은 CLI가 아닌 **Azure 포털에서 직접** 추가되었습니다(2절 참고).

## 5. 연결 방법

### 포털의 [연결] 페이지
`mysql-advdev-lkm` 리소스 → 왼쪽 메뉴 **[연결]**에서 Azure CLI / mysql CLI / 각종 언어별 연결 문자열 예시를 제공합니다(연결 문자열 자체는 본 문서에 기록하지 않음).

### 로컬 mysql 클라이언트로 접속 (명령 형태만, 암호는 대화형 입력)

```
mysql -h mysql-advdev-lkm.mysql.database.azure.com -u mysqladmin -p
```

`-p` 옵션만 주면 mysql 클라이언트가 실행 시점에 암호를 대화형으로 물어봅니다. 실제 접속은 사용자가 직접 수행합니다.

## 6. 포털에서 데이터베이스(labdb) 만들기 경로

`mysql-advdev-lkm` → **[설정] → [데이터베이스]** → **[+ 추가]** → 이름 `labdb` 입력 → **[저장]**. 저장 후 같은 화면의 데이터베이스 목록에서 `labdb`가 보이는지 확인합니다.

## 7. 소요 시간 메모

| 단계 | 비고 |
|---|---|
| 서버 생성(`create`) | 서버 자체 프로비저닝은 완료됐으나, 명령 마지막 단계에서 InternalServerError로 실패 보고됨(실제로는 서버는 Ready 상태) |
| 방화벽 규칙 추가(CLI) | 4회 재시도(약 2분) 모두 실패 |
| 방화벽 규칙 추가(포털) | 사용자가 직접 수행, 이후 조회로 즉시 확인됨 |

## 8. 검증 (인수조건)

| 조건 | 결과 | 비고 |
|---|---|---|
| (a) 서버 상태가 Ready | O | 3절 |
| (b) SKU·스토리지·백업 보존이 계획한 값과 일치 | O | Standard_B1ms / 20GiB / 7일 모두 일치 |
| (c) 방화벽에 0.0.0.0/0 규칙이 없음 | O | 4절 — AllowMyIP(내 IP 단일)만 존재 |
| (d) 암호가 어떤 파일에도 없음 | O | 스크립트(F5_mysql_flexible.ps1)에도 `<ADMIN_PASSWORD>` placeholder만 존재, 실제 값은 사용자가 직접 입력하고 어디에도 기록하지 않음 |

4가지 모두 **O**.

---

**실습 후 반드시 리소스 그룹을 삭제하세요.**
