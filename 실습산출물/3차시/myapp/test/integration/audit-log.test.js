const test = require('node:test');
const assert = require('node:assert');

// 03_테스트시나리오.xlsx [통합] 시트의 TC-I8~I10에 대응.
// 감사로그(누가·언제·무엇)가 실제 이벤트마다 기록되는지 GET /api/audit-log(관리자 전용)로 검증한다.
const BASE_URL = process.env.BASE_URL || 'http://localhost:4000';
const ALLOW_WRITE = (process.env.ALLOW_WRITE || 'true').toLowerCase() === 'true';

async function postJson(pathname, body) {
  const res = await fetch(BASE_URL + pathname, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}
async function deleteJson(pathname) {
  const res = await fetch(BASE_URL + pathname, { method: 'DELETE' });
  return { status: res.status, body: await res.json() };
}
async function getAuditLog(limit = 20) {
  const res = await fetch(`${BASE_URL}/api/audit-log?role=admin&limit=${limit}`);
  assert.strictEqual(res.status, 200, 'GET /api/audit-log(관리자)는 200이어야 한다');
  return res.json();
}

test('TC-I8: 비관리자는 감사로그를 조회할 수 없다(403)', async () => {
  const res = await fetch(`${BASE_URL}/api/audit-log`);
  assert.strictEqual(res.status, 403);
});

test('TC-I9: 레포 분석 실행 시 audit_log에 "누가·언제·무엇"이 기록된다', { timeout: 20000 }, async () => {
  if (!ALLOW_WRITE) return;
  const before = await getAuditLog(1);
  const beforeMaxId = before[0]?.id || 0;

  await postJson('/api/analyze', { repoUrl: 'https://github.com/octocat/Hello-World' });

  const after = await getAuditLog(20);
  const entry = after.find((r) => r.id > beforeMaxId && r.action === 'analyze');
  assert.ok(entry, 'analyze 액션이 감사로그에 기록되어야 한다');
  assert.ok(entry.actor_role === 'admin' || entry.actor_role === 'user', '누가(actor_role)가 기록되어야 한다');
  assert.ok(entry.at && !Number.isNaN(Date.parse(entry.at)), '언제(at)가 유효한 시각이어야 한다');
  assert.ok(['success', 'failed'].includes(entry.result), '결과(result)가 기록되어야 한다');
  assert.ok(entry.detail && entry.detail.includes('github.com'), '무엇(detail)에 대상 레포 정보가 남아야 한다');
});

test('TC-I10: 관리자 전용 기능(이력 삭제) 사용 시 audit_log에 성공/거부가 각각 기록된다', { timeout: 20000 }, async () => {
  if (!ALLOW_WRITE) return;
  // 1) 감사로그 확인용 분석 1건 생성
  const analyzed = await postJson('/api/analyze', { repoUrl: 'https://github.com/octocat/Spoon-Knife' });
  const id = analyzed.body.analysisId;

  // 2) 비관리자로 삭제 시도 → 403 + audit_log에 forbidden 기록
  const forbidden = await deleteJson(`/api/analyses/${id}`);
  assert.strictEqual(forbidden.status, 403);

  const afterForbidden = await getAuditLog(10);
  const forbiddenEntry = afterForbidden.find((r) => r.action === 'delete-analysis' && r.result === 'forbidden' && r.detail?.includes(String(id)));
  assert.ok(forbiddenEntry, '권한 없는 삭제 시도가 감사로그에 forbidden으로 기록되어야 한다');

  // 3) 관리자로 삭제 → 200 + audit_log에 success 기록
  const deleted = await deleteJson(`/api/analyses/${id}?role=admin`);
  assert.strictEqual(deleted.status, 200);

  const afterSuccess = await getAuditLog(10);
  const successEntry = afterSuccess.find((r) => r.action === 'delete-analysis' && r.result === 'success' && r.detail?.includes(String(id)));
  assert.ok(successEntry, '관리자 삭제 성공이 감사로그에 기록되어야 한다');
  assert.strictEqual(successEntry.actor_role, 'admin');
});
