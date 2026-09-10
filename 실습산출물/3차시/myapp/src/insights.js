// README·구조·커밋을 바탕으로 "이 프로젝트가 무엇인지" 요약 문장과 "어떤 아키텍처 패턴을 따르는지"를
// 규칙 기반(휴리스틱)으로 도출한다. AI 요약이 아니라 명시적 규칙에 따른 추정이므로, 항상 "추정" 문구를 붙인다.

// README 원문에서 배지·이미지·헤딩을 제외한 첫 문단(사람이 읽는 설명 문장)을 뽑아낸다.
function extractReadmeExcerpt(readmeText, maxLen = 220) {
  if (!readmeText) return '';
  const lines = readmeText.split('\n');
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith('#')) continue; // 헤딩
    if (line.startsWith('![') || line.startsWith('[![')) continue; // 이미지/배지
    if (line.startsWith('<')) continue; // HTML 태그(배지 모음 등)
    const cleaned = line
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // [text](url) -> text
      .replace(/[*_`]/g, '')
      .trim();
    if (cleaned.length < 10) continue; // 너무 짧은 줄(구분선 등)은 건너뜀
    return cleaned.length > maxLen ? cleaned.slice(0, maxLen - 1) + '…' : cleaned;
  }
  return '';
}

// 단어 집합 기준 유사도(자카드 계수). 설명과 README 첫 문단이 "Node." vs "Node.js"처럼
// 사소한 표기 차이만 있는 사실상 같은 문장인 경우를 걸러내기 위한 용도.
function wordOverlapRatio(a, b) {
  const words = (s) => new Set(s.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, '').split(/\s+/).filter(Boolean));
  const wa = words(a);
  const wb = words(b);
  if (wa.size === 0 || wb.size === 0) return 0;
  let common = 0;
  for (const w of wa) if (wb.has(w)) common++;
  return common / Math.min(wa.size, wb.size);
}

// "무엇을 위한 프로젝트인지" 한두 문장을 도출한다.
function deriveTopic({ description, readmeExcerpt, topLang }) {
  const parts = [];
  if (description && description.trim()) {
    parts.push(description.trim().replace(/\s+/g, ' '));
  }
  const isDuplicate = readmeExcerpt && parts.some((p) => wordOverlapRatio(p, readmeExcerpt) >= 0.6);
  if (readmeExcerpt && !isDuplicate) {
    parts.push(readmeExcerpt);
  }
  if (parts.length === 0) {
    return topLang && topLang !== '알 수 없음'
      ? `레포 설명과 README가 없어 자동으로 주제를 도출할 수 없었습니다. 파일 구성상 주로 **${topLang}**로 작성된 프로젝트로 보입니다(추정).`
      : '레포 설명·README·언어 통계가 모두 없어 주제를 도출할 수 없었습니다(빈 레포이거나 정보 부족).';
  }
  return parts.join(' — ');
}

// 최상위 디렉터리/파일 이름을 바탕으로 아키텍처 패턴을 규칙 기반으로 추정한다.
function inferArchitecture({ topLevelDirs, topLevelFiles }) {
  const dirNames = (topLevelDirs || []).map((d) => d.name.toLowerCase());
  const fileNames = (topLevelFiles || []).map((f) => f.toLowerCase());
  const has = (names) => names.some((n) => dirNames.includes(n));

  if (has(['packages', 'apps']) && dirNames.length >= 3) {
    return '**모노레포(monorepo)** 구조로 추정됩니다 — 여러 하위 패키지/앱을 한 저장소에서 함께 관리하는 형태입니다.';
  }
  if (has(['client', 'frontend', 'web']) && has(['server', 'backend', 'api'])) {
    return '**프론트엔드/백엔드 분리** 구조로 추정됩니다 — 클라이언트와 서버 코드가 별도 디렉터리로 나뉘어 있습니다.';
  }
  const mvcHits = ['controllers', 'models', 'views', 'routes'].filter((n) => dirNames.includes(n)).length;
  if (mvcHits >= 2) {
    return '**MVC(Model-View-Controller)** 패턴을 따르는 것으로 추정됩니다 — controllers/models/views/routes 등 역할별 디렉터리가 분리되어 있습니다.';
  }
  if (dirNames.includes('src') && (dirNames.includes('test') || dirNames.includes('tests')) &&
      (fileNames.includes('package.json') || fileNames.includes('setup.py') || fileNames.includes('cargo.toml'))) {
    return '**단일 라이브러리/패키지** 구조로 추정됩니다 — `src/`(구현)와 `test(s)/`(테스트)가 표준적으로 분리되어 있습니다.';
  }
  if (dirNames.length === 0) {
    return '최상위 디렉터리가 거의 없는 **평면(flat) 구조**입니다 — 소규모 스크립트/샘플 성격의 레포로 추정됩니다.';
  }
  return `뚜렷한 표준 패턴(모노레포/프론트-백엔드 분리/MVC 등)은 발견되지 않았습니다 — 최상위 디렉터리(${dirNames.slice(0, 5).map((d) => `\`${d}/\``).join(', ')} 등) 구성에 따른 일반적인 프로젝트 구조로 추정됩니다.`;
}

module.exports = { extractReadmeExcerpt, deriveTopic, inferArchitecture };
