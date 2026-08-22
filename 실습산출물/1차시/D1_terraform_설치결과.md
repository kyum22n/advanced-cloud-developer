# Terraform 설치 결과

## 요약

| 항목 | 내용 |
|---|---|
| 설치 여부 | 설치됨 (신규 설치, winget) |
| 설치 방법 | `winget install -e --id Hashicorp.Terraform` (성공, zip 수동 설치 불필요) |
| 버전 | Terraform v1.15.8 (windows_amd64) |
| 설치 경로 | `C:\Users\LG\AppData\Local\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe\terraform.exe` |
| PATH 등록 여부 | 등록됨 — **User PATH**에 위 경로 1건만 등록 (winget이 설치 중 자동 등록, 중복 없음) |
| Machine PATH 수정 여부 | 불필요 — 수행하지 않음 (User PATH만으로 모든 세션에서 정상 실행됨, 관리자 권한 불필요) |
| `C:\Terraform` 폴더(zip 방식) | 생성하지 않음 — winget 설치가 성공하여 zip 수동 설치 단계는 건너뜀 |

## 검증 (인수조건)

| 조건 | 결과 | 비고 |
|---|---|---|
| (a) `terraform version` 정상 출력 | O | `Terraform v1.15.8 / on windows_amd64` |
| (b) 임의 경로(`C:\`)에서도 실행 | O | `cd C:\` 후 `terraform version` 정상 동작 확인 |
| (c) PATH 중복 없음 | O | User PATH에 동일 경로 1건만 존재, Machine PATH는 미변경 |

## 진행 로그

1. `terraform version` 실행 → 미설치 확인 (`CommandNotFoundException`).
2. `winget install -e --id Hashicorp.Terraform --accept-source-agreements --accept-package-agreements --silent` 실행 → 1.15.8 다운로드/설치 성공, winget이 자체적으로 PATH(alias) 등록 ("Command line alias added: terraform").
3. winget 설치 성공으로 zip 수동 설치 및 관리자 권한 Machine PATH 등록(3단계)은 **수행하지 않음** (불필요).
4. 현재 세션 PATH를 Machine+User 값으로 갱신 후 `C:\` 로 이동하여 `terraform version` 및 실행 경로(`Get-Command terraform`) 확인 → 정상.
5. User/Machine PATH를 각각 조회하여 Terraform 관련 경로 중복 여부 확인 → User PATH에 1건만 존재, 중복 없음.

## 참고
- 새로 여는 터미널부터는 별도 조치 없이 `terraform` 명령이 바로 동작합니다 (이미 User PATH에 반영됨).
- 관리자 권한이 필요한 Machine PATH 등록 단계는 winget 설치 성공으로 인해 실행하지 않았습니다. 만약 모든 사용자 계정에서 공통으로 사용해야 하는 요구가 있다면, 이후 관리자 권한 PowerShell에서 별도 확인 후 진행할 수 있습니다.
