# Azure Files 실습 결과 (6-2 스토리지 계정 재사용)

이니셜: `lkm` / 리전: `koreacentral` / 리소스 그룹: `rg-advdev-lkm-data` (신규 생성 없음, 기존 재사용)

## 1. 재사용 계정 확인

`az storage account list --resource-group rg-advdev-lkm-data` 결과, 6-2에서 만든 **stadvdevlkm6305** 계정 1개만 존재함을 확인했고, 신규 계정을 만들지 않고 그대로 재사용했습니다.

## 2. 파일 공유 생성

| 항목 | 값 |
|---|---|
| 이름 | lab-share |
| 할당량 | 5 GB |
| 생성 결과 | Name: lab-share / ResourceGroup: rg-advdev-lkm-data / ShareQuota: 5 |

## 3. 권한 관련 이슈 및 해결

Blob 실습(F2)과 동일한 패턴으로, Azure Files 데이터 평면 작업에도 별도 처리가 필요했습니다.

1. `az storage file upload --auth-mode login` 최초 시도 시 `--enable-file-backup-request-intent is required for file share OAuth` 오류 → 해당 플래그 추가.
2. 플래그 추가 후에도 `You do not have the required permissions...` 오류 → Blob과는 다른 역할인 **`Storage File Data Privileged Contributor`**를 이 스토리지 계정 범위로만 부여 후, RBAC 전파 대기(약 60~70초, 4회 재시도) 후 업로드 성공.

즉 같은 계정 안에서도 **Blob 데이터 접근 역할**과 **Files 데이터 접근 역할**은 서로 다른 별개의 RBAC 역할입니다.

## 4. 업로드 파일 및 검증

| 항목 | 값 |
|---|---|
| 업로드 파일 | share-test.txt (내용: `2026-08-06 15:20 KST / lkm`) |
| 업로드 방식 | `az storage file upload` (`--auth-mode login --enable-file-backup-request-intent`, 계정 키 미사용) |
| `az storage file list` 결과 | Name: share-test.txt / Content Length: 27 / Type: file |

### 포털에서 확인하는 경로

[스토리지 계정: stadvdevlkm6305] → [파일 공유] → [lab-share] → 파일 목록에서 `share-test.txt` 확인

### Windows 네트워크 드라이브 연결 방법 (설명만, 미실행)

포털에서 lab-share를 열고 **[연결]** 버튼을 클릭하면 Windows용 PowerShell 스크립트가 자동 생성됩니다. 이 스크립트는 `net use Z: \\stadvdevlkm6305.file.core.windows.net\lab-share ...` 형태의 명령으로, **SMB 프로토콜(TCP 445번 포트)**을 통해 공유를 드라이브 문자로 마운트합니다. 회사·기관 네트워크에서 445번 포트 아웃바운드가 차단되어 있으면 이 방식은 실패하며, 이 경우 VPN 경유 또는 Azure Files의 REST(File Sync 등) 대안을 검토해야 합니다. 이번 실습에서는 **실제 마운트를 수행하지 않았습니다.**

## 5. 같은 계정 안 컨테이너 + 파일 공유 공존 증명

| 조회 명령 | 결과 |
|---|---|
| `az storage container list --account-name stadvdevlkm6305` | lab-images (F2에서 생성) |
| `az storage share-rm list --storage-account stadvdevlkm6305 --resource-group rg-advdev-lkm-data` | lab-share (본 실습에서 생성), ShareQuota: 5 |

동일한 스토리지 계정(`stadvdevlkm6305`) 안에 Blob 컨테이너(`lab-images`)와 파일 공유(`lab-share`)가 **동시에 존재**함을 조회 결과로 확인했습니다.

## 6. Blob 컨테이너 vs 파일 공유 비교 (실제 결과 기반)

| 기준 | Blob 컨테이너 (lab-images) | 파일 공유 (lab-share) |
|---|---|---|
| 접근 프로토콜 | REST(HTTPS) — `az storage blob upload/list` 등 REST 기반 CLI 명령만으로 동작 | REST + **SMB** — CLI는 REST를 쓰지만, 실사용은 SMB(445포트)로 드라이브 마운트하여 접근 |
| 계층 구조 | 계정 → 컨테이너 → Blob (1단계 평면 구조, `/`는 이름의 일부일 뿐) | 계정 → 공유 → 디렉터리 → 파일 (실제 폴더 트리 구조, `ShareQuota`로 용량 상한 지정) |
| 동시 다중 접근 | 여러 클라이언트의 동시 읽기는 자유롭지만, 파일 잠금 개념 없이 REST 호출 단위로 접근 | 여러 VM/PC가 **동시에 파일 잠금까지 지원하며** 같은 드라이브처럼 열고 쓰기 가능(이번 실습에서 `LeaseState: available / LeaseStatus: unlocked`로 확인) |
| 대표 사용 사례 | 이미지 서빙, 백업 아카이브(이번 실습 F2의 upload-test.txt) | 여러 서버가 공유하는 설정/문서 폴더(이번 실습의 share-test.txt) |
| 마이그레이션 적합 시나리오 | 신규 앱이 REST API로 직접 파일을 다루는 경우에 적합 | 기존 온프레미스 파일 서버(SMB 공유 폴더)를 코드 변경 없이 그대로 옮기는 리프트 앤 시프트에 적합 |

## 7. 검증 (인수조건)

| 조건 | 결과 | 비고 |
|---|---|---|
| (a) lab-share 생성됨 | O | ShareQuota: 5 확인 |
| (b) 파일 목록에 업로드 파일이 보임 | O | `az storage file list` 결과에 share-test.txt 확인 |
| (c) 같은 스토리지 계정에 컨테이너와 파일 공유가 함께 존재 | O | 5절 조회 결과(container list + share-rm list) 모두 stadvdevlkm6305 기준 |
| (d) 비교표 5개 항목 완성 | O | 6절 — 프로토콜/계층구조/동시접근/사용사례/마이그레이션 5개 모두 작성 |

4가지 모두 **O**.

---

**참고**: 이 계정(stadvdevlkm6305)은 Blob·Files 실습을 함께 재사용 중이므로, 별도 정리 지시가 있기 전까지 삭제하지 마세요.
