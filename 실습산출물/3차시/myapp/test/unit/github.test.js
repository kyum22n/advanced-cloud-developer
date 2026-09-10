const test = require('node:test');
const assert = require('node:assert');
const { parseRepoUrl, summarizeTree, mapGithubError } = require('../../src/github');

test('parseRepoUrl: 정상 URL 파싱', () => {
  const r = parseRepoUrl('https://github.com/octocat/Hello-World');
  assert.deepStrictEqual(r, { owner: 'octocat', repo: 'Hello-World' });
});

test('parseRepoUrl: 끝에 슬래시/.git 있어도 파싱', () => {
  assert.deepStrictEqual(parseRepoUrl('https://github.com/octocat/Hello-World/'), {
    owner: 'octocat',
    repo: 'Hello-World',
  });
  assert.deepStrictEqual(parseRepoUrl('https://github.com/octocat/Hello-World.git'), {
    owner: 'octocat',
    repo: 'Hello-World',
  });
});

test('parseRepoUrl: 잘못된 형식은 null', () => {
  assert.strictEqual(parseRepoUrl('not-a-valid-url'), null);
  assert.strictEqual(parseRepoUrl(''), null);
  assert.strictEqual(parseRepoUrl(undefined), null);
});

test('summarizeTree: 최상위 디렉터리별 파일 수 집계(포트폴리오 구조 요약)', () => {
  const tree = [
    { path: 'src/index.js', type: 'blob' },
    { path: 'src/utils/a.js', type: 'blob' },
    { path: 'test/a.test.js', type: 'blob' },
    { path: 'README.md', type: 'blob' },
    { path: 'src', type: 'tree' }, // 디렉터리 노드는 집계에서 제외
  ];
  const summary = summarizeTree(tree, false);
  assert.strictEqual(summary.totalFiles, 4);
  assert.deepStrictEqual(summary.topLevelFiles, ['README.md']);
  assert.deepStrictEqual(summary.topLevelDirs, [{ name: 'src', fileCount: 2 }, { name: 'test', fileCount: 1 }]);
  assert.strictEqual(summary.truncated, false);
});

test('mapGithubError: 404는 "비공개/미존재" 안내로 매핑된다 (AC4)', () => {
  const mapped = mapGithubError({ status: 404, message: 'Not Found' });
  assert.strictEqual(mapped.status, 404);
  assert.match(mapped.message, /비공개 레포이거나 존재하지 않는 레포/);
});

test('mapGithubError: 403(Rate Limit)은 429와 재시도 시각 안내로 매핑된다 (AC5)', () => {
  const resetEpoch = 1893456000; // 2030-01-01T00:00:00Z
  const mapped = mapGithubError({
    status: 403,
    message: 'API rate limit exceeded',
    response: { headers: { 'x-ratelimit-reset': String(resetEpoch) } },
  });
  assert.strictEqual(mapped.status, 429);
  assert.match(mapped.message, /GitHub API 호출 한도를 초과했습니다/);
  assert.match(mapped.message, /2030-01-01T00:00:00\.000Z/);
});

test('mapGithubError: 그 외 오류는 502로 매핑된다', () => {
  const mapped = mapGithubError({ status: 500, message: 'boom' });
  assert.strictEqual(mapped.status, 502);
});
