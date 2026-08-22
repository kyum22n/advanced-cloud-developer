# Frontend — HTML5 (바닐라 JavaScript)

| 항목 | 값 |
| --- | --- |
| 빌드 | **없음** — 정적 파일 그대로 |
| 서빙 | nginx 1.27 (정적 + `/api` 프록시) |
| 정적 검증 | ESLint(`eslint:recommended`) · `node --check` |
| E2E 선택자 | `data-testid` 고정 |

## 실행

```powershell
# 파이썬 내장 서버로 즉시 확인 (API 는 별도 기동 필요)
python -m http.server 5500 --directory public
```

## 이 구현이 강조하는 것

- **빌드 단계가 없다** — 파일을 열면 그대로 동작합니다. 배포 파이프라인이 가장 단순합니다.
- **`textContent` 만 사용** — `innerHTML` 은 입력값이 마크업으로 해석되어 XSS 통로가 됩니다.
- **`data-testid` 고정** — 화면 문구가 바뀌어도 E2E 테스트가 깨지지 않습니다.
