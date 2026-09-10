'use strict';
/**
 * E2E 테스트 — 03_테스트시나리오.xlsx [E2E] 시트의 TC-E1~E7을 코드 테스트로 옮긴 것.
 * BASE_URL 로 대상 환경을 바꾼다. 캡처는 test/e2e/캡처/ 에 저장.
 */
const { test, expect } = require('@playwright/test');
const path = require('path');

const SHOT = path.join(__dirname, '캡처');
const ENV = process.env.APP_ENV || 'dev';
const ALLOW_WRITE = String(process.env.ALLOW_WRITE || 'true').toLowerCase() === 'true';

test.describe('레포 인사이트 E2E', () => {
  test('TC-E1 (AC1): 메인화면 초기 렌더', async ({ page }) => {
    await page.goto('/index.html');
    await expect(page.locator('#analyzeBtn')).toBeVisible();
    await expect(page.locator('#repoUrl')).toBeVisible();
    await page.screenshot({ path: path.join(SHOT, `${ENV}_01_초기화면.png`), fullPage: true });
  });

  test('TC-E2 (AC1): 레포 URL 입력 상태 확인', async ({ page }) => {
    await page.goto('/index.html');
    await page.fill('#repoUrl', 'https://github.com/octocat/Hello-World');
    await expect(page.locator('#repoUrl')).toHaveValue('https://github.com/octocat/Hello-World');
    await page.screenshot({ path: path.join(SHOT, `${ENV}_02_실행_입력.png`), fullPage: true });
  });

  test('TC-E3 (AC1): 분석 결과 화면 확인(프로젝트 구조·차트·리포트)', async ({ page }) => {
    test.skip(!ALLOW_WRITE, '읽기 전용 환경에서는 건너뜁니다(운영 스모크)');
    await page.goto('/index.html');
    await page.fill('#repoUrl', 'https://github.com/octocat/Hello-World');
    await page.click('#analyzeBtn');
    await expect(page.locator('#resultCard')).toBeVisible({ timeout: 15000 });
    await expect(page.locator('#structureBox')).not.toBeEmpty();
    await expect(page.locator('#reportPreview')).toContainText('프로젝트 구조');
    await page.screenshot({ path: path.join(SHOT, `${ENV}_03_결과확인_차트리포트.png`), fullPage: true });
  });

  test('TC-E4 (AC4): 존재하지 않는 레포 예외 화면 확인', async ({ page }) => {
    test.skip(!ALLOW_WRITE, '읽기 전용 환경에서는 건너뜁니다(운영 스모크)');
    await page.goto('/index.html');
    await page.fill('#repoUrl', 'https://github.com/this-org-does-not-exist-xyz/private-tool');
    await page.click('#analyzeBtn');
    await expect(page.locator('#errorBox')).toBeVisible({ timeout: 15000 });
    await expect(page.locator('#errorBox')).toContainText('비공개 레포이거나 존재하지 않는 레포');
    await page.screenshot({ path: path.join(SHOT, `${ENV}_04_예외처리.png`), fullPage: true });
  });

  test('TC-E5 (AC3): 이력 목록 화면 확인', async ({ page }) => {
    await page.goto('/history.html');
    await expect(page.locator('#rows')).toBeVisible();
    await page.screenshot({ path: path.join(SHOT, `${ENV}_05_이력목록.png`), fullPage: true });
  });

  test('TC-E6/TC-E7 (AC6/AC2): Notion 업로드 결과 화면 확인', async ({ page }) => {
    test.skip(!ALLOW_WRITE, '읽기 전용 환경에서는 건너뜁니다(운영 스모크)');
    await page.goto('/index.html');
    await page.fill('#repoUrl', 'https://github.com/octocat/Hello-World');
    await page.click('#analyzeBtn');
    await expect(page.locator('#resultCard')).toBeVisible({ timeout: 15000 });
    await page.click('#notionBtn');
    // 중간 상태("업로드 중...")도 비어 있지 않은 텍스트이므로, 최종 상태 문구가 나타날 때까지 기다린다.
    // NOTION_TOKEN 설정 환경 → "업로드 완료", 미설정 환경 → "업로드 실패(HTTP 401)"
    await expect(page.locator('#notionStatus')).toContainText(/업로드 완료|업로드 실패/, { timeout: 15000 });
    await page.screenshot({ path: path.join(SHOT, `${ENV}_06_Notion업로드결과.png`), fullPage: true });
  });
});
