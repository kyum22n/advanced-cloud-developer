# Frontend — Vue 3 (Vite)

| 항목 | 값 |
| --- | --- |
| 런타임 | Vue 3.5 (Composition API · `<script setup>`) |
| 빌드 | Vite 5 |
| 정적 검증 | ESLint + `eslint-plugin-vue`(vue3-recommended) · `vite build` |
| E2E 선택자 | HTML5 구현과 **동일한 `data-testid`** |

## 실행

```powershell
npm install
npm run dev            # http://localhost:5173 (API 는 8080 으로 프록시)
```

## 정적 검증

```powershell
npm run verify:static  # lint + build
```

## HTML5 구현과 무엇이 다른가

| 관점 | HTML5 | Vue |
| --- | --- | --- |
| 화면 갱신 | DOM 을 직접 만들고 지운다 | **상태(ref)를 바꾸면 자동 반영** |
| 재사용 | 함수로 나눈다 | **컴포넌트**로 나눈다 |
| XSS | `textContent` 를 직접 지켜야 한다 | **기본이 이스케이프**(`v-html` 은 ESLint 로 금지) |
| 빌드 | 없음 | 필요(Vite) |
| E2E | **`data-testid` 가 같으므로 같은 테스트가 통과한다** | 동일 |

> 🔑 **두 구현의 `data-testid` 가 동일하다는 점이 핵심입니다.** 프런트엔드를 교체해도 E2E 테스트는 그대로 씁니다.
