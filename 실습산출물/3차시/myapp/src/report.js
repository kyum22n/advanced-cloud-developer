const { extractReadmeExcerpt, deriveTopic, inferArchitecture } = require('./insights');

function buildReportMarkdown(analysis) {
  const { owner, repo, repoUrl, defaultBranch, headSha, license, description, languageStats, commits, structure, readmeText, collectedAt } = analysis;

  const topLang = languageStats[0]?.language || '알 수 없음';
  const langTable = languageStats.length
    ? languageStats.map((l) => `| ${l.language} | ${l.ratio}% |`).join('\n')
    : '| (언어 통계 없음) | - |';

  const commitList = commits.length
    ? commits
        .slice(0, 30)
        .map((c) => `- \`${c.sha.slice(0, 7)}\` ${c.messageShort} (${c.committedAt ? c.committedAt.slice(0, 10) : '날짜 미상'})`)
        .join('\n')
    : '- 커밋 없음(빈 레포)';

  const structureLines = structure && (structure.topLevelDirs.length || structure.topLevelFiles.length)
    ? [
        ...structure.topLevelDirs.map((d) => `- \`${d.name}/\` — 파일 ${d.fileCount}개`),
        ...structure.topLevelFiles.map((f) => `- \`${f}\``),
      ].join('\n')
    : '- 구조 정보 없음(빈 레포이거나 조회 실패)';
  const structureNote = structure?.truncated
    ? '\n> ⚠ 레포 규모가 커서 GitHub API 응답이 일부 생략(truncated)되었습니다. 전체 구조는 GitHub에서 직접 확인하세요.'
    : '';

  const readmeExcerpt = extractReadmeExcerpt(readmeText);
  const topic = deriveTopic({ description, readmeExcerpt, topLang });
  const architecture = inferArchitecture({
    topLevelDirs: structure?.topLevelDirs || [],
    topLevelFiles: structure?.topLevelFiles || [],
  });

  return `# ${owner}/${repo} 프로젝트 분석 리포트

포트폴리오/이력서 첨부용으로 자동 생성된 리포트입니다.

## 개요
- 레포 URL: ${repoUrl}
- 설명: ${description || '(설명 없음)'}
- 기본 브랜치: ${defaultBranch}
- 분석 시점 HEAD SHA: \`${headSha}\`
- 라이선스: ${license}
- 수집 시각(UTC): ${collectedAt}

## 프로젝트 주제
${topic}

## 프로젝트 구조 (최상위 디렉터리 기준, 총 파일 ${structure?.totalFiles ?? '?'}개)
${structureLines}${structureNote}

## 아키텍처 패턴 (추정)
${architecture}

> 위 아키텍처 패턴은 디렉터리·파일 이름 기반의 규칙 추정이며, 실제 설계 의도와 다를 수 있습니다.

## 기술 스택 구성비
| 언어 | 비율 |
|---|---|
${langTable}

주요 기술스택은 **${topLang}** 입니다.

## 최근 커밋 요약 (최대 30건, 중복 SHA 제거)
${commitList}

> 커밋 작성자 이메일 등 개인식별 메타데이터는 이 리포트에 포함하지 않았습니다.
> 원본 코드는 재게시하지 않았으며, 변경 목적·범위 중심으로 요약했습니다.
`;
}

module.exports = { buildReportMarkdown };
