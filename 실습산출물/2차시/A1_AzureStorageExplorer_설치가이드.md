# Azure Storage Explorer 다운로드 및 설치 가이드

작성일: 2026-08-08

## 1. 목적

Azure Storage 계정(Blob, Files 등)을 GUI로 탐색·관리하기 위해 로컬 PC에 **Azure Storage Explorer**를 설치한다.

## 2. 사전 확인

설치 전 로컬 PC에 이미 설치되어 있는지 확인:

```powershell
Test-Path "$env:LOCALAPPDATA\Programs\Microsoft Azure Storage Explorer\StorageExplorer.exe"
winget list --id Microsoft.Azure.StorageExplorer
```

- 확인 결과: 미설치 상태 확인 → 신규 설치 진행

## 3. 다운로드 및 설치 (winget 사용)

winget(Windows Package Manager)을 통해 Microsoft 공식 서명 설치파일을 다운로드·설치했다.

```powershell
winget search "Storage Explorer"
# Name                             Id                              Version Source
# Microsoft Azure Storage Explorer Microsoft.Azure.StorageExplorer 1.44.0  winget

winget install --id Microsoft.Azure.StorageExplorer -e --accept-package-agreements --accept-source-agreements
```

### 설치 로그 요약

```
Found Microsoft Azure Storage Explorer [Microsoft.Azure.StorageExplorer] Version 1.44.0
Downloading https://github.com/microsoft/AzureStorageExplorer/releases/download/v1.44.0/StorageExplorer-windows-x64.exe
Successfully verified installer hash
Starting package install...
Successfully installed
```

| 항목 | 값 |
|---|---|
| 패키지 ID | Microsoft.Azure.StorageExplorer |
| 버전 | 1.44.0 |
| 배포 채널 | winget (winget 소스, Microsoft 공식 GitHub 릴리스) |
| 설치 파일 무결성 | 설치 해시 검증 성공 (Successfully verified installer hash) |
| 설치 경로 | `C:\Users\LG\AppData\Local\Programs\Microsoft Azure Storage Explorer\StorageExplorer.exe` |

> 참고: winget 검색 결과 `Microsoft.AzureStorageExplorer`(구 ID)는 존재하지 않았고, 현재 배포 ID는 `Microsoft.Azure.StorageExplorer`임.

## 4. 실행 확인

설치 완료 후 프로그램을 실행하여 정상 구동을 확인했다.

```powershell
Start-Process "C:\Users\LG\AppData\Local\Programs\Microsoft Azure Storage Explorer\StorageExplorer.exe"
```

- 실행 결과: 프로세스 `StorageExplorer` 정상 기동 확인 (PID 14280, 2026-08-08 13:24:49 시작)

## 5. 다음 단계 (참고)

최초 실행 시 Azure 계정 로그인(또는 연결 문자열/공유 액세스 서명으로 개별 스토리지 계정 연결)이 필요하다. 로그인 시 사용할 계정은 [[2차시_동일vm생성_결과산출물]] 문서에서 사용 중인 구독(Azure in Open, `kyumni207@o.shinhan.ac.kr`)과 일치 여부를 확인 후 진행할 것을 권장한다.
