const test = require('node:test');
const assert = require('node:assert');
const { extractReadmeExcerpt, deriveTopic, inferArchitecture } = require('../../src/insights');

test('extractReadmeExcerpt: 배지·헤딩·이미지를 건너뛰고 첫 설명 문단을 뽑는다', () => {
  const readme = `# My Project\n\n![badge](https://img.shields.io/badge/x-y)\n\n[![ci](url)](url2)\n\nThis project analyzes repos and generates portfolio reports.\n\n## Usage\n...`;
  const excerpt = extractReadmeExcerpt(readme);
  assert.match(excerpt, /analyzes repos and generates portfolio reports/);
});

test('extractReadmeExcerpt: README가 없으면 빈 문자열', () => {
  assert.strictEqual(extractReadmeExcerpt(''), '');
  assert.strictEqual(extractReadmeExcerpt(undefined), '');
});

test('deriveTopic: 설명과 README 첫 문단이 사실상 같은 문장이면 중복 제거한다', () => {
  const topic = deriveTopic({
    description: 'Fast, unopinionated, minimalist web framework for node.',
    readmeExcerpt: 'Fast, unopinionated, minimalist web framework for Node.js.',
    topLang: 'JavaScript',
  });
  // "—"로 두 문장이 이어붙는 형태가 아니라 하나만 남아야 한다
  assert.ok(!topic.includes(' — '), `중복 제거가 안 됨: ${topic}`);
});

test('deriveTopic: 서로 다른 내용이면 설명 + README 둘 다 포함한다', () => {
  const topic = deriveTopic({
    description: 'My first repository on GitHub!',
    readmeExcerpt: 'Hello World!',
    topLang: 'HTML',
  });
  assert.match(topic, /My first repository on GitHub!/);
  assert.match(topic, /Hello World!/);
});

test('deriveTopic: 설명·README가 모두 없으면 언어 기반 추정 문구로 대체한다', () => {
  const topic = deriveTopic({ description: '', readmeExcerpt: '', topLang: 'Python' });
  assert.match(topic, /Python/);
  assert.match(topic, /추정/);
});

test('inferArchitecture: packages/apps 디렉터리가 여러 개면 모노레포로 추정한다', () => {
  const result = inferArchitecture({
    topLevelDirs: [{ name: 'packages' }, { name: 'apps' }, { name: 'scripts' }],
    topLevelFiles: ['package.json'],
  });
  assert.match(result, /모노레포/);
});

test('inferArchitecture: client/server 디렉터리가 있으면 프론트-백엔드 분리로 추정한다', () => {
  const result = inferArchitecture({
    topLevelDirs: [{ name: 'client' }, { name: 'server' }],
    topLevelFiles: [],
  });
  assert.match(result, /프론트엔드\/백엔드 분리/);
});

test('inferArchitecture: controllers/models/views가 있으면 MVC로 추정한다', () => {
  const result = inferArchitecture({
    topLevelDirs: [{ name: 'controllers' }, { name: 'models' }, { name: 'views' }],
    topLevelFiles: [],
  });
  assert.match(result, /MVC/);
});

test('inferArchitecture: 디렉터리가 없으면 평면 구조로 추정한다', () => {
  const result = inferArchitecture({ topLevelDirs: [], topLevelFiles: ['index.html'] });
  assert.match(result, /평면\(flat\)/);
});
