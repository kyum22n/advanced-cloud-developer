# Backend — Node.js (NestJS)

| 항목 | 값 |
| --- | --- |
| 런타임 | Node.js 20 · NestJS 10 · TypeScript 5 |
| DB 접근 | `pg` (Pool) |
| 정적 검증 | `tsc --noEmit`(strict) · ESLint(@typescript-eslint) |
| 계약 | [`개발/공통/openapi.yaml`](../../공통/openapi.yaml) |

## 실행

```powershell
npm install
npm run start:dev
```

## 정적 검증

```powershell
npm run verify:static      # typecheck + lint
```

## 이 구현이 강조하는 것

- **`strict: true` + `noUnusedLocals`** — 타입 검사만으로 잡히는 결함을 배포 전에 제거합니다.
- **`@typescript-eslint/no-explicit-any: error`** — `any` 로 타입을 무력화하지 못하게 막습니다.
- **`pg` 의 `password` 에 함수 전달** — prd 에서 연결마다 최신 Entra 토큰을 씁니다.
