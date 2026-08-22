"use strict";
/** 단위 테스트 — 외부 의존 없이 순수 로직만 검증한다. (node --test) */
const test = require("node:test");
const assert = require("node:assert");
const { isoWeek, summarizeByWeek, dedupeById, maskPii } = require("../../src/lib/summary");

test("U-01 isoWeek: 같은 주의 월요일과 일요일은 동일한 주차", () => {
  assert.strictEqual(isoWeek(new Date("2026-03-02T00:00:00Z")), isoWeek(new Date("2026-03-08T00:00:00Z")));
});

test("U-02 summarizeByWeek: 주차별 건수와 합계를 집계", () => {
  const rows = [
    { id: 1, amount: 100, createdAt: "2026-03-02T10:00:00Z" },
    { id: 2, amount: 200, createdAt: "2026-03-05T10:00:00Z" },
    { id: 3, amount: 50,  createdAt: "2026-03-10T10:00:00Z" },
  ];
  const out = summarizeByWeek(rows);
  assert.strictEqual(out.length, 2);
  assert.strictEqual(out[0].count, 2);
  assert.strictEqual(out[0].amount, 300);
});

test("U-03 summarizeByWeek: 빈 배열이면 빈 결과 (예외 아님)", () => {
  assert.deepStrictEqual(summarizeByWeek([]), []);
});

test("U-04 summarizeByWeek: 배열이 아니면 TypeError", () => {
  assert.throws(() => summarizeByWeek(null), TypeError);
});

test("U-05 dedupeById: 같은 id는 마지막 값만 남는다", () => {
  const out = dedupeById([{ id: 1, v: "a" }, { id: 1, v: "b" }, { id: 2, v: "c" }]);
  assert.strictEqual(out.length, 2);
  assert.strictEqual(out.find(x => x.id === 1).v, "b");
});

test("U-06 maskPii: 이름·사번 마스킹", () => {
  assert.strictEqual(maskPii("홍길동", "name"), "홍*동");
  assert.strictEqual(maskPii("20231234", "empno"), "****1234");
});
