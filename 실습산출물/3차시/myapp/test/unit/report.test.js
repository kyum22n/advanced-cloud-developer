const test = require('node:test');
const assert = require('node:assert');
const { buildReportMarkdown } = require('../../src/report');

test('buildReportMarkdown: 기술스택·커밋 요약이 포함되고 이메일 등 개인정보는 포함하지 않는다', () => {
  const md = buildReportMarkdown({
    owner: 'octocat',
    repo: 'Hello-World',
    repoUrl: 'https://github.com/octocat/Hello-World',
    defaultBranch: 'master',
    headSha: 'abc1234',
    license: 'MIT',
    description: 'test repo',
    languageStats: [{ language: 'HTML', bytes: 100, ratio: 76 }],
    commits: [{ sha: 'abc1234567', messageShort: 'fix bug', committedAt: '2026-01-01T00:00:00Z' }],
    collectedAt: '2026-01-02T00:00:00Z',
  });

  assert.match(md, /HTML/);
  assert.match(md, /76%/);
  assert.match(md, /fix bug/);
  assert.doesNotMatch(md, /@/); // 이메일 등 개인식별정보 미포함 확인
});

test('buildReportMarkdown: 커밋 없는 빈 레포는 "커밋 없음" 표기', () => {
  const md = buildReportMarkdown({
    owner: 'a', repo: 'b', repoUrl: 'https://github.com/a/b', defaultBranch: 'main',
    headSha: 'main', license: '라이선스 미확인', description: '', languageStats: [], commits: [],
    collectedAt: '2026-01-01T00:00:00Z',
  });
  assert.match(md, /커밋 없음/);
  assert.match(md, /언어 통계 없음/);
});
