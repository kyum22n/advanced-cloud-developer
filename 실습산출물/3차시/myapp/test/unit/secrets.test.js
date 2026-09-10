const test = require('node:test');
const assert = require('node:assert');
const { resolveSecretSource, secretsDiagnostics } = require('../../src/secrets');
const { workloadIdentityAvailable } = require('../../src/azureIdentity');

test('workloadIdentityAvailable: 3개 환경변수가 모두 있어야 true (dev/stg는 false여야 함)', () => {
  assert.strictEqual(workloadIdentityAvailable({}), false);
  assert.strictEqual(workloadIdentityAvailable({ AZURE_CLIENT_ID: 'x' }), false);
  assert.strictEqual(
    workloadIdentityAvailable({ AZURE_CLIENT_ID: 'x', AZURE_TENANT_ID: 'y', AZURE_FEDERATED_TOKEN_FILE: '/var/run/x' }),
    true
  );
});

test('resolveSecretSource: dev/stg(워크로드 ID 없음) — env에 값 있으면 env, 없으면 unset', () => {
  assert.strictEqual(resolveSecretSource('GITHUB_TOKEN', { GITHUB_TOKEN: 'ghp_x' }), 'env');
  assert.strictEqual(resolveSecretSource('GITHUB_TOKEN', {}), 'unset');
});

test('resolveSecretSource: prd에서 CSI가 이미 동기화했으면(env 있음) env를 그대로 쓴다(중복 호출 방지)', () => {
  const env = {
    GITHUB_TOKEN: 'ghp_x',
    AZURE_CLIENT_ID: 'c', AZURE_TENANT_ID: 't', AZURE_FEDERATED_TOKEN_FILE: '/f',
    KEYVAULT_NAME: 'kv-myapp-prd',
  };
  assert.strictEqual(resolveSecretSource('GITHUB_TOKEN', env), 'env');
});

test('resolveSecretSource: prd에서 env가 비어 있고 워크로드 ID+KEYVAULT_NAME이 있으면 keyvault로 자가 복구', () => {
  const env = {
    AZURE_CLIENT_ID: 'c', AZURE_TENANT_ID: 't', AZURE_FEDERATED_TOKEN_FILE: '/f',
    KEYVAULT_NAME: 'kv-myapp-prd',
  };
  assert.strictEqual(resolveSecretSource('GITHUB_TOKEN', env), 'keyvault');
});

test('resolveSecretSource: 워크로드 ID는 있어도 KEYVAULT_NAME이 없으면 unset(잘못된 구성 방어)', () => {
  const env = { AZURE_CLIENT_ID: 'c', AZURE_TENANT_ID: 't', AZURE_FEDERATED_TOKEN_FILE: '/f' };
  assert.strictEqual(resolveSecretSource('GITHUB_TOKEN', env), 'unset');
});

test('secretsDiagnostics: 실제 토큰 값은 절대 포함하지 않는다(출처만)', () => {
  const env = { GITHUB_TOKEN: 'ghp_super_secret_value_12345' };
  const diag = secretsDiagnostics(env);
  const serialized = JSON.stringify(diag);
  assert.doesNotMatch(serialized, /ghp_super_secret_value_12345/);
  assert.strictEqual(diag.sources.GITHUB_TOKEN, 'env');
  assert.strictEqual(diag.workloadIdentity, false);
});

test('secretsDiagnostics: 3개 비밀 모두 unset이면 workloadIdentity=false, 전부 unset으로 보고한다', () => {
  const diag = secretsDiagnostics({});
  assert.strictEqual(diag.sources.GITHUB_TOKEN, 'unset');
  assert.strictEqual(diag.sources.NOTION_TOKEN, 'unset');
  assert.strictEqual(diag.sources.NOTION_PARENT_PAGE_ID, 'unset');
});
