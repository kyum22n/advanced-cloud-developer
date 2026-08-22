/**
 * 주차 집계 — 외부 의존이 없는 순수 로직(U-A-01~05).
 * 설계 근거: 설계/공통/02_도메인·클래스설계서.md
 */
export interface ItemLike {
  id: number;
  title: string;
  amount: number;
  createdAt: string | Date;
}

export interface WeekSummary {
  week: string;
  count: number;
  amount: number;
}

/** ISO 8601 주차 문자열(YYYY-Www)을 만든다. */
export function isoWeek(value: string | Date): string {
  const d = new Date(value);
  const utc = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  // ISO 주차는 목요일이 속한 해를 기준으로 한다
  const day = utc.getUTCDay() || 7;
  utc.setUTCDate(utc.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((utc.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${utc.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

/** 주차별 건수·금액을 집계한다. 빈 배열은 예외가 아니라 빈 결과다. */
export function summarizeByWeek(items: ItemLike[]): WeekSummary[] {
  if (!Array.isArray(items)) {
    throw new TypeError('items must be an array');
  }
  const acc = new Map<string, WeekSummary>();
  for (const item of items) {
    const week = isoWeek(item.createdAt);
    const cur = acc.get(week) ?? { week, count: 0, amount: 0 };
    cur.count += 1;
    cur.amount += Number(item.amount) || 0;
    acc.set(week, cur);
  }
  return [...acc.values()].sort((a, b) => a.week.localeCompare(b.week));
}

/** 같은 id 가 여러 번 나오면 마지막 값만 남긴다. */
export function dedupeById<T extends { id: number }>(items: T[]): T[] {
  const byId = new Map<number, T>();
  for (const item of items) {
    byId.set(item.id, item);
  }
  return [...byId.values()];
}
