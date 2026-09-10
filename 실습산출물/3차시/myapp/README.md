# 레포 인사이트 · GitHub → Notion 포트폴리오 리포트 도구

개발자가 자신의 GitHub 공개 레포 URL을 입력하면 프로젝트 구조·커밋 히스토리·언어 통계를 분석해 기술스택·프로젝트 설명 리포트를 생성하고, 포트폴리오/이력서 정리용으로 Notion에 업로드(버튼 클릭)하는 도구입니다.

## 1. 설치

```bash
cd myapp
npm install
```

## 2. 환경변수 설정

`.env.example`을 복사해 `.env`를 만들고 값을 채웁니다. **`.env`는 git에 커밋되지 않습니다(.gitignore 처리됨).**

```bash
cp .env.example .env
```

| 변수 | 설명 | 필수 여부 |
|---|---|---|
| `GITHUB_TOKEN` | GitHub Personal Access Token (공개 레포 read 권한). [발급 링크](https://github.com/settings/tokens) | 선택(없으면 비인증 60회/시간 Rate Limit 적용) |
| `NOTION_TOKEN` | Notion Integration Token. [Notion Integrations](https://www.notion.so/my-integrations)에서 발급 | Notion 업로드 기능 사용 시 필수 |
| `NOTION_PARENT_PAGE_ID` | 리포트를 업로드할 상위 페이지 ID. 해당 페이지를 Integration과 **Connect** 해야 합니다 | Notion 업로드 기능 사용 시 필수 |
| `PORT` | 서버 포트 (기본 4000) | 선택 |

## 3. 실행

```bash
npm start
```

브라우저에서 `http://localhost:4000` 접속 (분석 실행 화면), `http://localhost:4000/history.html`에서 이력 확인.

## 4. 테스트

```bash
npm test
```

## 5. 사용 흐름

1. 메인 화면에서 GitHub 공개 레포 URL 입력 → "분석 실행"
2. 기술스택 구성비·최근 커밋 요약·생성된 Markdown 리포트 확인
3. "Notion에 업로드" 클릭 → Notion에 새 페이지 생성, 링크 표시
4. "이력 목록"에서 과거 분석 재조회

## 6. 보안·라이선스 주의점

- GitHub PAT, Notion Token 등 비밀값은 반드시 `.env`로만 관리하며 코드에 하드코딩하지 않습니다.
- 커밋 작성자 이메일 등 개인식별 메타데이터는 리포트·Notion 페이지에 포함하지 않습니다(마스킹).
- 비공개(private) 레포는 분석 대상에서 제외됩니다(GitHub API가 404를 반환하며 자동 차단).
- 코드 원문은 대량 인용하지 않고 변경 목적·범위 중심으로 요약합니다.
- 라이선스가 확인되지 않은 레포는 리포트에 "라이선스 미확인"으로 표시됩니다.
- 이 저장소 코드(Express/MIT, @octokit/rest/MIT, @notionhq/client/MIT, better-sqlite3/MIT)는 모두 MIT 라이선스 오픈소스를 사용합니다.

## 7. 데이터 저장

- `data/app.db` (SQLite, git 미포함) — 분석 이력·언어 통계·커밋 요약·리포트 원문·감사로그
