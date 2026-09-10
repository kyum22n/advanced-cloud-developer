require('dotenv').config();
const path = require('path');
const express = require('express');

const { db, logAudit } = require('./src/db');
const { analyzeRepo, GithubApiError } = require('./src/github');
const { buildReportMarkdown } = require('./src/report');
const { uploadReportToNotion, NotionApiError } = require('./src/notion');
const { secretsDiagnostics } = require('./src/secrets');

const app = express();
const APP_ENV = process.env.APP_ENV || 'local';

app.use(express.json());

// 실습 환경 특성상 단일 사용자 기준 간이 역할 스위치(?role=admin|user), 기본은 user
function currentRole(req) {
  return req.query.role === 'admin' ? 'admin' : 'user';
}

// 프로세스 생존 여부만 확인 — 의존성(DB 등) 상태와 무관하게 응답한다.
app.get('/healthz', (req, res) => {
  res.json({ status: 'ok', env: APP_ENV });
});

// 실제로 DB에 쿼리를 날려 연결 가능 여부를 확인한다(단순 프로세스 생존 여부와 구분).
app.get('/readyz', (req, res) => {
  try {
    db.prepare('SELECT 1').get();
    res.json({ status: 'ready' });
  } catch (err) {
    res.status(503).json({ status: 'not-ready', error: err.message });
  }
});

// 자격 증명 "값"은 절대 포함하지 않는다 — 어떤 방식으로 비밀을 구했는지(출처)만 보여준다.
app.get('/version', (req, res) => {
  res.json({ version: process.env.APP_VERSION || 'dev', env: APP_ENV, identity: secretsDiagnostics() });
});

app.use(express.static(path.join(__dirname, 'public')));

app.post('/api/analyze', async (req, res) => {
  const role = currentRole(req);
  const { repoUrl } = req.body || {};
  try {
    const analysis = await analyzeRepo(repoUrl);
    const markdown = buildReportMarkdown(analysis);

    const insertAnalysis = db.prepare(`
      INSERT INTO analysis (repo_url, owner, repo, default_branch, commit_sha, license, collected_at, status, error_reason)
      VALUES (@repoUrl,@owner,@repo,@defaultBranch,@headSha,@license,@collectedAt,'success',NULL)
    `);
    const info = insertAnalysis.run(analysis);
    const analysisId = info.lastInsertRowid;

    const insertLang = db.prepare(
      'INSERT INTO language_stat (analysis_id, language, bytes, ratio) VALUES (?,?,?,?)'
    );
    for (const l of analysis.languageStats) insertLang.run(analysisId, l.language, l.bytes, l.ratio);

    const insertCommit = db.prepare(
      'INSERT INTO commit_summary (analysis_id, sha, message_short, committed_at) VALUES (?,?,?,?)'
    );
    for (const c of analysis.commits) insertCommit.run(analysisId, c.sha, c.messageShort, c.committedAt);

    db.prepare('INSERT INTO report (analysis_id, content_md) VALUES (?,?)').run(analysisId, markdown);

    logAudit(role, 'analyze', 'success', analysis.repoUrl);
    res.json({ analysisId, analysis, markdown });
  } catch (err) {
    const status = err instanceof GithubApiError ? err.status : 500;
    logAudit(role, 'analyze', 'failed', `${repoUrl || ''} :: ${err.message}`);
    if (repoUrl) {
      const parsedOwnerRepo = String(repoUrl).replace(/^https?:\/\/github\.com\//i, '').replace(/\/$/, '');
      db.prepare(`
        INSERT INTO analysis (repo_url, owner, repo, default_branch, commit_sha, license, collected_at, status, error_reason)
        VALUES (?,?,?,NULL,NULL,NULL,?,'failed',?)
      `).run(repoUrl, parsedOwnerRepo.split('/')[0] || '', parsedOwnerRepo.split('/')[1] || '', new Date().toISOString(), err.message);
    }
    res.status(status).json({ error: err.message });
  }
});

app.get('/api/analyses', (req, res) => {
  const rows = db.prepare('SELECT * FROM analysis ORDER BY id DESC').all();
  res.json(rows);
});

app.get('/api/analyses/:id', (req, res) => {
  const analysis = db.prepare('SELECT * FROM analysis WHERE id=?').get(req.params.id);
  if (!analysis) return res.status(404).json({ error: '이력을 찾을 수 없습니다.' });
  const languageStats = db.prepare('SELECT * FROM language_stat WHERE analysis_id=?').all(req.params.id);
  const commits = db.prepare('SELECT * FROM commit_summary WHERE analysis_id=? ORDER BY id').all(req.params.id);
  const report = db.prepare('SELECT * FROM report WHERE analysis_id=?').get(req.params.id);
  res.json({ analysis, languageStats, commits, report });
});

// 관리자 전용: 분석 이력 삭제. 일반 사용자가 호출하면 403으로 차단한다(실제 접근 제어).
app.delete('/api/analyses/:id', (req, res) => {
  const role = currentRole(req);
  if (role !== 'admin') {
    logAudit(role, 'delete-analysis', 'forbidden', `analysisId=${req.params.id}`);
    return res.status(403).json({ error: '관리자만 이력을 삭제할 수 있습니다. URL에 ?role=admin을 추가하세요.' });
  }
  const analysis = db.prepare('SELECT * FROM analysis WHERE id=?').get(req.params.id);
  if (!analysis) return res.status(404).json({ error: '이력을 찾을 수 없습니다.' });

  db.prepare('DELETE FROM language_stat WHERE analysis_id=?').run(req.params.id);
  db.prepare('DELETE FROM commit_summary WHERE analysis_id=?').run(req.params.id);
  db.prepare('DELETE FROM report WHERE analysis_id=?').run(req.params.id);
  db.prepare('DELETE FROM analysis WHERE id=?').run(req.params.id);

  logAudit(role, 'delete-analysis', 'success', `analysisId=${req.params.id} (${analysis.owner}/${analysis.repo})`);
  res.json({ deleted: true, id: Number(req.params.id) });
});

app.post('/api/analyses/:id/notion-upload', async (req, res) => {
  const role = currentRole(req);
  const analysis = db.prepare('SELECT * FROM analysis WHERE id=?').get(req.params.id);
  const report = db.prepare('SELECT * FROM report WHERE analysis_id=?').get(req.params.id);
  if (!analysis || !report) return res.status(404).json({ error: '이력을 찾을 수 없습니다.' });

  try {
    const result = await uploadReportToNotion({
      title: `${analysis.owner}/${analysis.repo} 기술 분석 리포트`,
      markdown: report.content_md,
    });
    db.prepare('UPDATE report SET notion_page_id=?, notion_url=?, uploaded_at=? WHERE analysis_id=?').run(
      result.pageId,
      result.url,
      new Date().toISOString(),
      analysis.id
    );
    logAudit(role, 'notion-upload', 'success', result.url);
    res.json({ notionUrl: result.url });
  } catch (err) {
    const status = err instanceof NotionApiError ? err.status : 502;
    logAudit(role, 'notion-upload', 'failed', err.message);
    res.status(status).json({ error: err.message });
  }
});

// 관리자 전용: 감사로그 조회(누가·언제·무엇을 했는지). 최신 N건.
app.get('/api/audit-log', (req, res) => {
  const role = currentRole(req);
  if (role !== 'admin') {
    return res.status(403).json({ error: '관리자만 감사로그를 조회할 수 있습니다. URL에 ?role=admin을 추가하세요.' });
  }
  const limit = Math.min(Number(req.query.limit) || 50, 200);
  const rows = db.prepare('SELECT * FROM audit_log ORDER BY id DESC LIMIT ?').all(limit);
  res.json(rows);
});

app.get('/api/env-status', (req, res) => {
  // 'unset'이 아니면(=env 또는 keyvault로 조달 가능하면) "설정됨"으로 본다. 값은 절대 포함하지 않는다.
  const { sources } = secretsDiagnostics();
  res.json({
    githubTokenSet: sources.GITHUB_TOKEN !== 'unset',
    notionTokenSet: sources.NOTION_TOKEN !== 'unset',
    notionParentPageIdSet: sources.NOTION_PARENT_PAGE_ID !== 'unset',
  });
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`레포 인사이트 서버 실행 중: http://localhost:${PORT}`));
