const { Octokit } = require('@octokit/rest');
const { getSecret } = require('./secrets');

function parseRepoUrl(repoUrl) {
  const m = String(repoUrl || '').trim().match(
    /^https?:\/\/github\.com\/([^/\s]+)\/([^/\s#]+?)(\.git)?\/?$/i
  );
  if (!m) return null;
  return { owner: m[1], repo: m[2] };
}

class GithubApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// GITHUB_TOKEN은 env(k8s Secret)에 있으면 그대로, 없고 워크로드 ID가 있으면 Key Vault에서
// 직접 가져온다 — 어느 쪽이든 "환경이 스스로" 고른다(src/secrets.js).
async function makeClient() {
  const token = await getSecret('GITHUB_TOKEN', 'github-token');
  return new Octokit({ auth: token || undefined });
}

// 커밋 메시지 첫 줄만, 작성자 이메일 등 개인식별정보는 절대 포함하지 않는다(마스킹 원칙).
function shortMessage(fullMessage) {
  const firstLine = String(fullMessage || '').split('\n')[0];
  return firstLine.length > 100 ? firstLine.slice(0, 97) + '...' : firstLine;
}

// octokit이 던진 원본 에러를 앱 표준 에러(GithubApiError)로 변환한다.
// 순수 함수로 분리해 실제 GitHub API 호출 없이도 404/403(rate limit) 매핑을 단위 테스트할 수 있게 한다.
function mapGithubError(err) {
  if (err.status === 404) {
    return new GithubApiError(404, '비공개 레포이거나 존재하지 않는 레포입니다.');
  }
  if (err.status === 403) {
    const reset = err.response?.headers?.['x-ratelimit-reset'];
    const resetAt = reset ? new Date(Number(reset) * 1000).toISOString() : '알 수 없음';
    return new GithubApiError(429, `GitHub API 호출 한도를 초과했습니다. 재시도 가능 시각(UTC): ${resetAt}`);
  }
  return new GithubApiError(502, `GitHub API 호출 중 오류가 발생했습니다: ${err.message}`);
}

async function analyzeRepo(repoUrl) {
  const parsed = parseRepoUrl(repoUrl);
  if (!parsed) {
    throw new GithubApiError(400, 'GitHub 레포 URL 형식이 올바르지 않습니다. 예: https://github.com/owner/repo');
  }
  const { owner, repo } = parsed;
  const octokit = await makeClient();

  let repoMeta;
  try {
    const res = await octokit.repos.get({ owner, repo });
    repoMeta = res.data;
  } catch (err) {
    throw mapGithubError(err);
  }

  if (repoMeta.private) {
    throw new GithubApiError(404, '비공개 레포이거나 존재하지 않는 레포입니다.');
  }

  const [languagesRes, commitsRes, treeRes, readmeRes] = await Promise.all([
    octokit.repos.listLanguages({ owner, repo }).catch(() => ({ data: {} })),
    octokit.repos
      .listCommits({ owner, repo, per_page: 30, sha: repoMeta.default_branch })
      .catch(() => ({ data: [] })),
    octokit.git
      .getTree({ owner, repo, tree_sha: repoMeta.default_branch, recursive: '1' })
      .catch(() => ({ data: { tree: [], truncated: false } })),
    octokit.repos.getReadme({ owner, repo }).catch(() => null), // 없으면(404) null — 정상 케이스로 처리
  ]);

  const languages = languagesRes.data || {};
  const totalBytes = Object.values(languages).reduce((a, b) => a + b, 0);
  const languageStats = Object.entries(languages)
    .map(([language, bytes]) => ({
      language,
      bytes,
      ratio: totalBytes ? Math.round((bytes / totalBytes) * 1000) / 10 : 0,
    }))
    .sort((a, b) => b.bytes - a.bytes);

  // SHA 기준 중복 제거
  const seen = new Set();
  const commits = [];
  for (const c of commitsRes.data || []) {
    if (seen.has(c.sha)) continue;
    seen.add(c.sha);
    commits.push({
      sha: c.sha,
      messageShort: shortMessage(c.commit?.message),
      committedAt: c.commit?.author?.date || null,
    });
  }

  const headSha = commits[0]?.sha || repoMeta.default_branch;
  const structure = summarizeTree(treeRes.data?.tree || [], treeRes.data?.truncated);
  const readmeText = readmeRes?.data?.content
    ? Buffer.from(readmeRes.data.content, 'base64').toString('utf-8')
    : '';

  return {
    owner,
    repo,
    repoUrl: `https://github.com/${owner}/${repo}`,
    defaultBranch: repoMeta.default_branch,
    description: repoMeta.description || '',
    license: repoMeta.license?.spdx_id && repoMeta.license.spdx_id !== 'NOASSERTION'
      ? repoMeta.license.spdx_id
      : '라이선스 미확인',
    stars: repoMeta.stargazers_count,
    headSha,
    languageStats,
    commits,
    structure,
    readmeText,
    collectedAt: new Date().toISOString(),
  };
}

// 레포 파일 트리를 최상위 디렉터리 단위로 요약(포트폴리오 설명용 "프로젝트 구조" 절 재료).
function summarizeTree(tree, truncated) {
  const topLevelFiles = [];
  const dirFileCounts = new Map();

  for (const item of tree) {
    if (item.type !== 'blob') continue; // 파일만 집계(디렉터리 노드 자체는 제외)
    const slashIdx = item.path.indexOf('/');
    if (slashIdx === -1) {
      topLevelFiles.push(item.path);
    } else {
      const topDir = item.path.slice(0, slashIdx);
      dirFileCounts.set(topDir, (dirFileCounts.get(topDir) || 0) + 1);
    }
  }

  const topLevelDirs = Array.from(dirFileCounts.entries())
    .map(([name, fileCount]) => ({ name, fileCount }))
    .sort((a, b) => b.fileCount - a.fileCount);

  return {
    totalFiles: tree.filter((t) => t.type === 'blob').length,
    topLevelDirs,
    topLevelFiles: topLevelFiles.sort(),
    truncated: Boolean(truncated),
  };
}

module.exports = { analyzeRepo, parseRepoUrl, summarizeTree, mapGithubError, GithubApiError };
