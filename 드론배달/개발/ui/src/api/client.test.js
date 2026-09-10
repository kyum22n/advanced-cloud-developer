import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { api, ApiError } from './client.js'

/**
 * API 클라이언트 테스트.
 *
 * 검증 대상은 «서버와의 규약»이다 —
 * 멱등 키를 보내는가, 상관 ID 를 보내는가, Problem Details 를 제대로 해석하는가.
 */
describe('API 클라이언트', () => {
  let fetchMock

  beforeEach(() => {
    fetchMock = vi.fn()
    globalThis.fetch = fetchMock
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  function ok(body, status = 200) {
    return Promise.resolve({
      ok: true,
      status,
      text: () => Promise.resolve(JSON.stringify(body)),
    })
  }

  function fail(problem, status) {
    return Promise.resolve({
      ok: false,
      status,
      text: () => Promise.resolve(JSON.stringify(problem)),
    })
  }

  it('배달 예약 시 Idempotency-Key 를 보낸다 — 없으면 재시도가 이중 접수가 된다', async () => {
    fetchMock.mockReturnValue(ok({ deliveryId: 'dlv-0001' }, 202))

    await api.createDelivery({ ownerId: 'acc-0001' })

    const [, init] = fetchMock.mock.calls[0]
    expect(init.headers['Idempotency-Key']).toBeTruthy()
  })

  it('모든 요청에 상관 ID 를 보낸다 — 분산 추적의 열쇠', async () => {
    fetchMock.mockReturnValue(ok({ status: 'PENDING' }))

    await api.getStatus('dlv-0001')

    const [, init] = fetchMock.mock.calls[0]
    expect(init.headers['X-Correlation-Id']).toBeTruthy()
  })

  it('매 요청마다 다른 상관 ID 를 만든다', async () => {
    fetchMock.mockReturnValue(ok({}))

    await api.getStatus('dlv-1')
    await api.getStatus('dlv-2')

    const first = fetchMock.mock.calls[0][1].headers['X-Correlation-Id']
    const second = fetchMock.mock.calls[1][1].headers['X-Correlation-Id']
    expect(first).not.toBe(second)
  })

  it('Problem Details 를 ApiError 로 바꾼다', async () => {
    fetchMock.mockReturnValue(fail({
      type: 'https://fabrikam.example/errors/invalid-state-transition',
      title: '허용되지 않는 상태 전이',
      detail: 'IN_TRANSIT 상태의 배달은 취소할 수 없습니다.',
      correlationId: 'req-abc123',
    }, 409))

    await expect(api.cancelDelivery('dlv-0001')).rejects.toThrowError(ApiError)

    try {
      await api.cancelDelivery('dlv-0001')
    } catch (e) {
      expect(e.status).toBe(409)
      expect(e.type).toContain('invalid-state-transition')
      expect(e.correlationId).toBe('req-abc123')
      expect(e.isUserFixable).toBe(true)
      expect(e.isRetryable).toBe(false)
    }
  })

  it('503 은 재시도 가능한 오류로 분류한다', async () => {
    fetchMock.mockReturnValue(fail({ title: '일시적으로 접수할 수 없습니다' }, 503))

    try {
      await api.createDelivery({})
    } catch (e) {
      expect(e.isRetryable).toBe(true)
      expect(e.isUserFixable).toBe(false)
    }
  })

  it('204 응답은 null 을 돌려준다', async () => {
    fetchMock.mockReturnValue(Promise.resolve({ ok: true, status: 204, text: () => Promise.resolve('') }))
    await expect(api.cancelDelivery('dlv-0001')).resolves.toBeNull()
  })

  it('배달 ID 를 URL 에 넣을 때 인코딩한다', async () => {
    fetchMock.mockReturnValue(ok({}))
    await api.getStatus('dlv/../etc')

    const [url] = fetchMock.mock.calls[0]
    expect(url).not.toContain('/../')
  })
})
