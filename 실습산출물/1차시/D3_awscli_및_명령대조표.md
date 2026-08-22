# AWS CLI v2 설치 결과 및 Azure CLI ↔ AWS CLI 명령 대조표

## 설치 결과

| 항목 | 내용 |
|---|---|
| 설치 여부 | 신규 설치 (winget) |
| 설치 방법 | `winget install -e --id Amazon.AWSCLI` |
| 버전 | aws-cli/2.36.16, Python/3.14.6, Windows/11, exe/AMD64 |
| PATH 등록 | 정상 — 세션 PATH 갱신 후 임의 폴더(`C:\`)에서 `aws --version` 실행 확인 |
| 자격 증명(Access Key 등) | **입력·저장하지 않음** — 이 단계에서는 설치·버전 확인까지만 수행, 로그인/API 호출 미시도 |

## 검증 (인수조건)

| 조건 | 결과 | 비고 |
|---|---|---|
| (a) `aws --version` 출력 | O | `aws-cli/2.36.16 Python/3.14.6 Windows/11 exe/AMD64` |
| (b) 대조표 7개 항목 모두 채워짐 | O | 아래 표 참고 |
| (c) 자격 증명이 파일 어디에도 저장되지 않음 | O | Access Key/Secret Key를 어떤 명령·파일에도 입력하지 않았고, `aws configure`는 실행하지 않음(사용자 직접 실행 예정) |

---

## `aws configure` 입력 항목 안내 (실행은 직접 하시면 됩니다)

터미널에서 `aws configure`를 실행하면 아래 4가지를 순서대로 물어봅니다. **Access Key ID / Secret Access Key는 여기 문서나 저에게 공유하지 마시고, 프롬프트에 직접 입력해주세요.**

| 항목 | 의미 | 비고 |
|---|---|---|
| AWS Access Key ID | IAM 사용자(또는 역할)를 식별하는 공개 키 문자열 | IAM 콘솔 또는 관리자가 발급한 값. 일반적으로 `AKIA`로 시작 |
| AWS Secret Access Key | Access Key ID와 쌍을 이루는 비밀 키 (실제 인증에 사용) | **발급 시 1회만 표시됨** — 분실 시 재발급 필요, 절대 공유/커밋 금지 |
| Default region name | API 요청을 보낼 기본 AWS 리전 코드 | 예: `ap-northeast-2`(서울), `us-east-1`(버지니아) 등. 리전을 안 정하면 매 명령마다 `--region` 지정 필요 |
| Default output format | CLI 명령 결과의 기본 출력 형식 | `json` / `yaml` / `text` / `table` 중 선택. 스크립트용은 `json`, 사람이 보기엔 `table` 추천 |

설정 값은 `%USERPROFILE%\.aws\credentials`(키), `%USERPROFILE%\.aws\config`(리전/출력형식)에 로컬 저장되며, 이 문서나 저장소에는 어떤 값도 기록하지 않았습니다.

---

## Azure CLI ↔ AWS CLI 명령 대조표

| 작업 | Azure CLI | AWS CLI | 1:1로 맞지 않는 부분 |
|---|---|---|---|
| 리소스 그룹 생성 | `az group create` | 대응 개념 없음 (태그 또는 CloudFormation 스택으로 대체) | Azure는 "리소스 그룹"이 리소스의 논리적 컨테이너·수명주기 단위이지만, AWS는 이런 강제적 컨테이너가 없고 태그(Tag) 기반 분류나 CloudFormation/CDK 스택으로 묶음 관리를 대신함 |
| 가상 네트워크 생성 | `az network vnet create` | `aws ec2 create-vpc` | Azure VNet은 생성 시 주소공간만 지정하면 서브넷·라우팅이 비교적 자동 통합되지만, AWS VPC는 라우팅 테이블·인터넷 게이트웨이 등을 별도 리소스로 명시적으로 만들어 연결해야 함 |
| 서브넷 생성 | `az network vnet subnet create` | `aws ec2 create-subnet` | Azure는 서브넷 생성 시 NSG·라우팅 테이블 연결이 옵션으로 간편하게 붙지만, AWS는 서브넷 생성 후 라우팅 테이블 연결(`associate-route-table`)을 별도 명령으로 수행해야 함 |
| NAT 게이트웨이 생성 | `az network nat gateway create` | `aws ec2 create-nat-gateway` | AWS NAT 게이트웨이는 반드시 특정 서브넷에 배치되고 탄력적 IP(EIP)를 사전에 할당해 연결해야 하지만, Azure NAT 게이트웨이는 Public IP를 생성과 함께 더 유연하게 연결/재사용 가능 |
| 가상 머신 생성 | `az vm create` | `aws ec2 run-instances` | Azure `az vm create`는 이미지·네트워크·NIC·디스크를 한 명령으로 자동 프로비저닝해주는 경우가 많지만, AWS `run-instances`는 AMI ID·서브넷·보안그룹·키페어를 사전에 개별적으로 준비해 명시해야 함 |
| 오브젝트 스토리지 생성 | `az storage account create` | `aws s3api create-bucket` | Azure Storage Account는 Blob/File/Queue/Table 등 여러 서비스를 포괄하는 상위 계정 단위이고 그 안에 컨테이너를 또 만들어야 하지만, AWS S3 버킷은 그 자체로 바로 오브젝트 저장 단위라 계층 구조가 다름 |
| 관리형 MySQL 생성 | `az mysql flexible-server create` | `aws rds create-db-instance` | Azure Flexible Server는 명령 하나로 컴퓨팅·스토리지·네트워크가 묶여 생성되는 경우가 많지만, AWS RDS는 서브넷 그룹(`db-subnet-group`)과 보안그룹을 미리 만들어 옵션으로 넘겨야 하는 등 사전 준비 리소스가 더 많음 |

---

## 진행 로그

1. `aws --version` 실행 → 미설치 확인.
2. `winget install -e --id Amazon.AWSCLI` 실행 → 2.36.16 설치 성공.
3. 세션 PATH 갱신 후 `C:\`에서 `aws --version` 재확인 → 정상 동작.
4. 자격 증명(Access Key/Secret Key)은 어떤 단계에서도 입력·조회·저장하지 않았으며, `aws configure`는 실행하지 않음(사용자가 직접 실행할 예정).
