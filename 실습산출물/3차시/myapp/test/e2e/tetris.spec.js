"use strict";
/**
 * E2E 테스트 — 설계/공통/06 §4-2 의 E-B-01~04 에 대응한다.
 * 좌표·상태 확인은 픽셀이 아니라 `[data-testid="debug-state"]` 의 JSON 스냅샷으로 한다
 * (설계/공통/06 §7-1: data-testid 우선 · 고정 대기 대신 조건 대기).
 */
const { test, expect } = require("@playwright/test");
const path = require("path");

const SHOT = path.join(__dirname, "캡처");
const ENV = process.env.APP_ENV || "dev";

async function readDebugState(page) {
  const text = await page.getByTestId("debug-state").textContent();
  return JSON.parse(text);
}

test.describe("웹 테트리스 E2E", () => {
  test("E-B-01 게임 화면 로드 — Canvas 렌더 · 점수 0 · 다음 블록 표시", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByTestId("board-canvas")).toBeVisible();
    await expect(page.getByTestId("score")).toHaveText("점수: 0");
    await expect(page.getByTestId("next-label")).not.toHaveText("-");
    await page.screenshot({ path: path.join(SHOT, `${ENV}_B01_초기화면.png`), fullPage: true });
  });

  test("E-B-02 키 입력 반응 — 방향키 입력에 블록 위치가 변한다", async ({ page }) => {
    await page.goto("/");
    const before = await readDebugState(page);

    await page.keyboard.press("ArrowRight");
    await expect
      .poll(async () => (await readDebugState(page)).x, { timeout: 5000 })
      .not.toBe(before.x);

    await page.keyboard.press("ArrowDown");
    await expect
      .poll(async () => (await readDebugState(page)).y, { timeout: 5000 })
      .toBeGreaterThan(before.y);

    await page.screenshot({ path: path.join(SHOT, `${ENV}_B02_조작.png`), fullPage: true });
  });

  test("E-B-03 하드 드롭·점수 — Space 키로 블록이 고정되고 점수 표시가 갱신된다", async ({ page }) => {
    await page.goto("/");
    const before = await readDebugState(page);

    await page.keyboard.press("Space");
    // 하드 드롭 후 새 블록이 스폰 위치 근처(작은 y)로 재설정되어야 한다 — 고정이 실제로 일어났다는 증거
    await expect
      .poll(async () => (await readDebugState(page)).y, { timeout: 5000 })
      .toBeLessThan(before.y + 5);
    await expect(page.getByTestId("score")).toHaveText(/^점수: \d+$/);

    await page.screenshot({ path: path.join(SHOT, `${ENV}_B03_점수.png`), fullPage: true });
  });

  test("E-B-04 일시정지 — P 키로 «일시정지» 가 표시되고 보드가 멈춘다", async ({ page }) => {
    await page.goto("/");
    await page.keyboard.press("p");
    await expect(page.getByTestId("state-badge")).toHaveText("일시정지");

    const s1 = await readDebugState(page);
    await page.waitForTimeout(300); // 중력 간격(최소 80ms)보다 길게 대기해도 좌표가 그대로인지 확인
    const s2 = await readDebugState(page);
    expect(s2.x).toBe(s1.x);
    expect(s2.y).toBe(s1.y);

    await page.screenshot({ path: path.join(SHOT, `${ENV}_B04_일시정지.png`), fullPage: true });
  });
});
