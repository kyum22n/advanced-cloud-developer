/**
 * API 클라이언트.
 *
 * 이 파일이 «서버와의 계약»을 지키는 유일한 지점이다.
 * 컴포넌트가 fetch 를 직접 부르면 헤더 규약과 오류 처리가 여기저기 흩어진다.
 */

/** 상관 ID — 화면 오류와 서버 로그를 이어 주는 열쇠. */
function newCorrelationId() {
  return (globalThis.crypto?.randomUUID?.())
    || `req-${Date.now()}-${Math.random().toString(16).slice(2)}`
}

/** 멱등 키 — 같은 요청을 재시도해도 배달이 두 번 만들어지지 않게 한다. */
function newIdempotencyKey() {
  return (globalThis.crypto?.randomUUID?.())
    || `idem-${Date.now()}-${Math.random().toString(16).slice(2)}`
}

/**
 * RFC 9457 Problem Details 를 다루기 쉬운 오류로 바꾼다.
 *
 * 클라이언트는 title(문구)이 아니라 type(URI)으로 분기해야 한다 —
 * 문구는 바뀔 수 있지만 type 은 계약이기 때문이다.
 */
export class ApiError extends Error {
  constructor(problem, status) {
    super(problem?.detail || problem?.title || `요청에 실패했습니다 (${status})`)
    this.name = 'ApiError'
    this.type = problem?.type || null
    this.status = status
    this.correlationId = problem?.correlationId || null
    this.fieldErrors = problem?.errors || []
  }

  /** 사용자가 «고쳐서 다시 보내면» 되는 오류인가. */
  get isUserFixable() {
    return this.status === 400 || this.status === 409 || this.status === 422
  }

  /** 잠시 뒤 재시도하면 되는 오류인가. */
  get isRetryable() {
    return this.status === 429 || this.status === 503 || this.status >= 500
  }
}

async function request(path, { method = 'GET', body, headers = {} } = {}) {
  const response = await fetch(path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Correlation-Id': newCorrelationId(),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  })

  if (response.status === 204) return null

  const text = await response.text()
  const payload = text ? JSON.parse(text) : null

  if (!response.ok) {
    throw new ApiError(payload, response.status)
  }
  return payload
}

export const api = {
  /**
   * 배달을 예약한다.
   *
   * 서버는 202 Accepted 를 돌려준다 — «접수했다»이지 «만들어졌다»가 아니다.
   * 그래서 곧바로 조회하면 404 일 수 있고, statusUrl 을 폴링해야 한다.
   */
  createDelivery(payload) {
    return request('/api/v1/deliveries', {
      method: 'POST',
      body: payload,
      headers: { 'Idempotency-Key': newIdempotencyKey() },
    })
  },

  getStatus(deliveryId) {
    return request(`/api/v1/deliveries/${encodeURIComponent(deliveryId)}/status`)
  },

  getDelivery(deliveryId) {
    return request(`/api/v1/deliveries/${encodeURIComponent(deliveryId)}`)
  },

  cancelDelivery(deliveryId, reason) {
    const q = reason ? `?reason=${encodeURIComponent(reason)}` : ''
    return request(`/api/v1/deliveries/${encodeURIComponent(deliveryId)}${q}`, { method: 'DELETE' })
  },

  getHistory(deliveryId) {
    return request(`/api/v1/history/${encodeURIComponent(deliveryId)}`)
  },

  listHistory({ ownerId, from, to, page = 0, size = 20 }) {
    const q = new URLSearchParams({ ownerId, from, to, page, size })
    return request(`/api/v1/history?${q}`)
  },
}
