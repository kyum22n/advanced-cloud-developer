const test = require('node:test');
const assert = require('node:assert');

// 03_테스트시나리오.xlsx [통합] 시트의 TC-I1~I7을 코드 테스트로 옮긴 것.
// BASE_URL: 배포된(또는 로컬 기동 중인) 앱 주소. ALLOW_WRITE=true 일 때만 쓰기(POST) 테스트를 실행한다.
const BASE_URL = process.env.BASE_URL || 'http://localhost:4000';
const ALLOW_WRITE = (process.env.ALLOW_WRITE || 'true').toLowerCase() === 'true';

async function getJson(pathname) {
  const res = await fetch(BASE_URL + pathname);
  return { status: res.status, body: await res.json() };
}
async function postJson(pathname, body) {
  const res = await fetch(BASE_URL + pathname, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

test('TC-I5 (AC3): GET /api/analyses 는 이력 배열을 반환한다', async () => {
  const { status, body } = await getJson('/api/analyses');
  assert.strictEqual(status, 200);
  assert.ok(Array.isArray(body));
});

test('TC-I2 (AC4): 잘못된 URL 형식은 400을 반환한다', async () => {
  if (!ALLOW_WRITE) return; // 쓰기 금지 환경(prd)에서는 스킵
  const { status, body } = await postJson('/api/analyze', { repoUrl: 'not-a-valid-url' });
  assert.strictEqual(status, 400);
  assert.match(body.error, /URL 형식이 올바르지 않습니다/);
});

test('TC-I1 (AC1) + TC-I4/TC-I7 (AC6/AC2): 정상 분석 후 Notion 업로드 경로를 검증한다', { timeout: 30000 }, async () => {
  if (!ALLOW_WRITE) return; // 쓰기 금지 환경(prd)에서는 스킵 — 운영 스모크는 읽기 전용이 원칙
  const analyzed = await postJson('/api/analyze', { repoUrl: 'https://github.com/octocat/Hello-World' });
  assert.strictEqual(analyzed.status, 200);
  assert.ok(analyzed.body.analysisId);
  assert.ok(analyzed.body.analysis.structure, '프로젝트 구조(structure) 필드가 있어야 한다');
  assert.ok(Array.isArray(analyzed.body.analysis.languageStats));

  const upload = await postJson(`/api/analyses/${analyzed.body.analysisId}/notion-upload`);
  if (upload.status === 200) {
    // TC-I7 (AC2): NOTION_TOKEN·NOTION_PARENT_PAGE_ID가 설정된 환경
    assert.ok(upload.body.notionUrl && upload.body.notionUrl.length > 0);
  } else {
    // TC-I4 (AC6): 미설정 환경 — 401이며 토큰 실값은 응답에 없어야 한다
    assert.strictEqual(upload.status, 401);
    assert.doesNotMatch(JSON.stringify(upload.body), /ntn_|secret_/);
  }
});
