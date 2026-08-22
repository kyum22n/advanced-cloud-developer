# Blob Storage 실습 결과

이니셜: `lkm` / 리전: `koreacentral` / 리소스 그룹: `rg-advdev-lkm-data` (신규, 네트워크 실습 리소스 그룹과 분리)

## 1. 스토리지 계정

| 항목 | 값 |
|---|---|
| 후보 3개 | stadvdevlkm6305, stadvdevlkm2364, stadvdevlkm0963 (`az storage account check-name` 결과 모두 `nameAvailable: true`) |
| 확정된 이름 | **stadvdevlkm6305** |
| SKU | Standard_ZRS |
| ProvisioningState | Succeeded |

**Standard_ZRS란**: 데이터를 같은 리전 내 서로 다른 물리적 영역(가용 영역) 3곳에 동기적으로 복제하는 "영역 중복 저장" 방식으로, 한 영역에 장애가 나도 데이터가 보존됩니다.

## 2. 컨테이너

| 항목 | 값 |
|---|---|
| 이름 | lab-images |
| 생성 결과 | Created: True (`--auth-mode login`, 계정 키 미사용) |

**"모든 Blob은 컨테이너 안에 있어야 한다"는 규칙**: Blob은 스토리지 계정에 직접 놓이지 않고 반드시 하나의 컨테이너에 속해야 합니다. 컨테이너는 Blob들을 담는 최상위(1단계) 분류 단위이자 접근 정책(공개/비공개)을 지정하는 경계이기 때문에, 파일을 올리기 전에 컨테이너부터 만들어야 합니다.

## 3. 권한 관련 이슈 및 해결

컨테이너 생성(관리 평면)은 구독 Owner 권한으로 성공했지만, Blob 업로드(데이터 평면) 시도 시 다음 오류가 발생했습니다.

```
You do not have the required permissions needed to perform this operation.
Depending on your operation, you may need to be assigned one of the following roles:
    "Storage Blob Data Owner" / "Storage Blob Data Contributor" / "Storage Blob Data Reader" ...
```

**원인**: Azure RBAC에서 "관리 권한(Owner)"과 "데이터 평면 접근 권한(Blob 읽기/쓰기)"은 별도 체계입니다. 구독 Owner라도 Blob 데이터 자체에 접근하려면 `Storage Blob Data Contributor` 같은 데이터 평면 역할을 별도로 부여받아야 합니다.

**조치**: 사용자 확인 후, 본 계정에 **이 스토리지 계정 범위로만** `Storage Blob Data Contributor` 역할을 부여(`az role assignment create`)했고, RBAC 전파 대기(약 60~70초, 4회 재시도) 후 업로드가 성공했습니다.

## 4. 업로드 파일 및 검증

| 항목 | 값 |
|---|---|
| 업로드 파일 | upload-test.txt (내용: `2026-08-06 15:00 KST / lkm`) |
| 업로드 방식 | `az storage blob upload` (`--auth-mode login`, 계정 키 미사용) |
| `az storage blob list` 결과 | Name: upload-test.txt / Blob Type: BlockBlob / Blob Tier: Hot / Length: 27 |

### 포털에서 확인하는 경로

[스토리지 계정: stadvdevlkm6305] → [데이터 저장소 → 컨테이너] → [lab-images] → 파일 목록에서 `upload-test.txt` 확인

## 5. 액세스 계층 변경 명령 (제안만, 미실행)

```
az storage blob set-tier --account-name stadvdevlkm6305 --container-name lab-images --name upload-test.txt --tier Cool --auth-mode login
az storage blob set-tier --account-name stadvdevlkm6305 --container-name lab-images --name upload-test.txt --tier Archive --auth-mode login
```

위 명령은 이번 실습에서 **실행하지 않았습니다.**

## 6. 검증 (인수조건)

| 조건 | 결과 | 비고 |
|---|---|---|
| (a) 스토리지 계정 생성 성공 | O | ProvisioningState: Succeeded |
| (b) 컨테이너 lab-images 존재 | O | Created: True |
| (c) Blob 목록에 업로드 파일이 보임 | O | `az storage blob list` 결과에 upload-test.txt 확인 |
| (d) 계정 키·연결 문자열이 어떤 파일에도 저장되지 않음 | O | 모든 명령에 `--auth-mode login` 사용, 키 조회 명령 자체를 실행하지 않았음 |

4가지 모두 **O**.

---

**이 계정은 다음 실습(Azure Files)에서 재사용하니 삭제하지 마세요.**
