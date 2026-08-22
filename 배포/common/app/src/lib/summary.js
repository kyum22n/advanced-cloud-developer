"use strict";
/**
 * 순수 로직 — 외부 의존(DB·네트워크) 없이 단위 테스트 가능한 계산 모듈.
 * 배포 환경이 달라져도 이 파일의 동작은 동일해야 한다(단위 테스트의 기준).
 */

/** ISO 주차 문자열(YYYY-Www) 반환 */
function isoWeek(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

/** 항목 배열을 주차별로 집계 — { week, count, amount } 배열 반환 */
function summarizeByWeek(items) {
  if (!Array.isArray(items)) throw new TypeError("items must be an array");
  const map = new Map();
  for (const it of items) {
    if (!it || !it.createdAt) continue;
    const wk = isoWeek(new Date(it.createdAt));
    const cur = map.get(wk) || { week: wk, count: 0, amount: 0 };
    cur.count += 1;
    cur.amount += Number(it.amount || 0);
    map.set(wk, cur);
  }
  return [...map.values()].sort((a, b) => a.week.localeCompare(b.week));
}

/** 중복 제거 — id 기준, 뒤에 온 값이 우선 */
function dedupeById(items) {
  const map = new Map();
  for (const it of items || []) if (it && it.id != null) map.set(it.id, it);
  return [...map.values()];
}

/** 개인정보 마스킹 — 이름은 가운데를, 사번은 뒤 4자리만 노출 */
function maskPii(value, kind = "name") {
  if (value == null) return value;
  const s = String(value);
  if (kind === "empno") return s.length <= 4 ? "****" : "*".repeat(s.length - 4) + s.slice(-4);
  if (s.length <= 1) return s;
  if (s.length === 2) return s[0] + "*";
  return s[0] + "*".repeat(s.length - 2) + s[s.length - 1];
}

module.exports = { isoWeek, summarizeByWeek, dedupeById, maskPii };
