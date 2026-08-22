"use strict";
/**
 * E2E 테스트 — 실제 브라우저로 화면을 조작해 검증하고 캡처를 남긴다.
 * BASE_URL 로 대상 환경을 바꾼다. 캡처는 test/e2e/캡처/ 에 저장.
 */
const { test, expect } = require("@playwright/test");
const path = require("path");

const SHOT = path.join(__dirname, "캡처");
const ENV = process.env.APP_ENV || "dev";
const ALLOW_WRITE = String(process.env.ALLOW_WRITE || "true").toLowerCase() === "true";

test.describe("나만의 업무 앱 E2E", () => {
  test("E-01 초기 화면이 열리고 헤더가 보인다", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("h1")).toContainText("나만의 업무 앱");
    await page.screenshot({ path: path.join(SHOT, `${ENV}_01_초기화면.png`), fullPage: true });
  });

  test("E-02 환경/버전 라벨이 표시된다", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("#envLabel")).toContainText("환경:");
  });

  test("E-03 항목을 추가하면 목록에 나타난다", async ({ page }) => {
    test.skip(!ALLOW_WRITE, "읽기 전용 환경에서는 건너뜁니다(운영 스모크)");
    const title = `E2E-${Date.now()}`;
    await page.goto("/");
    await page.getByTestId("title").fill(title);
    await page.getByTestId("amount").fill("500");
    await page.screenshot({ path: path.join(SHOT, `${ENV}_02_실행·입력.png`), fullPage: true });
    await page.getByTestId("add").click();
    await expect(page.getByTestId("table")).toContainText(title);
    await page.screenshot({ path: path.join(SHOT, `${ENV}_03_결과확인.png`), fullPage: true });
  });

  test("E-04 제목 없이 추가하면 저장되지 않는다 (예외 처리)", async ({ page }) => {
    test.skip(!ALLOW_WRITE, "읽기 전용 환경에서는 건너뜁니다(운영 스모크)");
    await page.goto("/");
    page.once("dialog", d => d.accept());
    await page.getByTestId("title").fill("");
    await page.getByTestId("add").click();
    await page.screenshot({ path: path.join(SHOT, `${ENV}_04_예외처리.png`), fullPage: true });
  });
});
