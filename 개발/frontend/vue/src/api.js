/**
 * API 클라이언트 — 계약은 개발/공통/openapi.yaml 을 따른다.
 * 화면 컴포넌트가 fetch 를 직접 부르지 않게 해, 계약 변경의 영향 범위를 한 파일로 좁힌다.
 */
const BASE = import.meta.env.VITE_API_BASE ?? '';

async function request(path, options = {}) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { Accept: 'application/json', ...(options.headers ?? {}) },
    ...options,
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const message = body.error ?? `요청이 실패했습니다 (HTTP ${res.status})`;
    const error = new Error(message);
    error.status = res.status;
    throw error;
  }
  return body;
}

export function fetchVersion() {
  return request('/version');
}

export function fetchItems() {
  return request('/api/items');
}

export function fetchSummary() {
  return request('/api/summary');
}

export function createItem(title, amount) {
  return request('/api/items', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, amount }),
  });
}
