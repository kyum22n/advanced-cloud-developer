import { ref, onUnmounted } from 'vue'
import { api } from '../api/client.js'

/**
 * 배달 추적 — 폴링.
 *
 * 왜 폴링인가 — WebSocket 은 게이트웨이·인증·재연결 처리가 붙어 복잡도가 크게 는다.
 * 배달 상태는 초 단위 정확도가 필요하지 않으므로, 3초 폴링으로 충분하다.
 * «필요 없는 실시간»을 넣지 않는 것도 설계다.
 *
 * 다만 두 가지는 지킨다.
 *   ① 배달이 끝나면 폴링을 멈춘다 — 무한 요청 방지
 *   ② 탭이 안 보이면 멈춘다 — 배터리·요금 낭비 방지
 */
export function useDeliveryTracking(intervalMs = 3000) {
  const status = ref(null)
  const error = ref(null)
  const loading = ref(false)
  const isPolling = ref(false)

  let timer = null
  let currentId = null

  const TERMINAL = ['COMPLETED', 'CANCELLED', 'FAILED', 'COMPENSATED']

  async function fetchOnce() {
    if (!currentId) return
    loading.value = true
    try {
      status.value = await api.getStatus(currentId)
      error.value = null

      // 배달이 끝났으면 더 물어볼 필요가 없다.
      if (TERMINAL.includes(status.value?.status)) {
        stop()
      }
    } catch (e) {
      // 404 는 «아직 생성되지 않음»일 수 있다 (202 접수 직후) — 계속 폴링한다.
      if (e.status === 404) {
        error.value = null
      } else {
        error.value = e
        if (!e.isRetryable) stop()
      }
    } finally {
      loading.value = false
    }
  }

  function start(deliveryId) {
    stop()
    currentId = deliveryId
    isPolling.value = true
    fetchOnce()
    timer = setInterval(() => {
      if (document.hidden) return          // 탭이 안 보이면 건너뛴다
      fetchOnce()
    }, intervalMs)
  }

  function stop() {
    if (timer) clearInterval(timer)
    timer = null
    isPolling.value = false
  }

  onUnmounted(stop)

  return { status, error, loading, isPolling, start, stop, refresh: fetchOnce }
}
