<script setup>
import { ref, watch, computed } from 'vue'
import { useDeliveryTracking } from '../composables/useDeliveryTracking.js'
import { api } from '../api/client.js'
import StatusBadge from '../components/StatusBadge.vue'
import ErrorPanel from '../components/ErrorPanel.vue'

const props = defineProps({
  deliveryId: { type: String, default: '' },
})

const input = ref(props.deliveryId || '')
const cancelError = ref(null)
const { status, error, loading, isPolling, start, stop } = useDeliveryTracking(3000)

// 라우트 파라미터로 들어오면 바로 추적을 시작한다.
watch(() => props.deliveryId, (id) => { if (id) { input.value = id; start(id) } }, { immediate: true })

const eta = computed(() => {
  const t = status.value?.eta?.arrivalTime
  if (!t) return null
  return new Date(t).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' })
})

const confidence = computed(() => {
  const c = status.value?.eta?.confidence
  return c == null ? null : `${Math.round(c * 100)}%`
})

const cancellable = computed(() =>
  ['PENDING', 'SCHEDULED'].includes(status.value?.status))

async function cancel() {
  cancelError.value = null
  try {
    await api.cancelDelivery(input.value, '사용자 요청')
  } catch (e) {
    cancelError.value = e
  }
}
</script>

<template>
  <section class="card">
    <h2>배달 추적</h2>

    <form
      class="inline-form"
      data-testid="tracking-form"
      @submit.prevent="start(input)"
    >
      <input
        v-model="input"
        placeholder="배달 번호 (예: dlv-7f3a9c)"
        data-testid="input-delivery-id"
        required
      >
      <button
        type="submit"
        data-testid="btn-track"
      >
        추적
      </button>
      <button
        v-if="isPolling"
        type="button"
        data-testid="btn-stop"
        @click="stop"
      >
        중지
      </button>
    </form>

    <ErrorPanel :error="error" />
    <ErrorPanel :error="cancelError" />

    <div
      v-if="status"
      class="tracking"
      data-testid="tracking-panel"
    >
      <div class="tracking__row">
        <span class="label">상태</span>
        <StatusBadge :status="status.status" />
      </div>

      <div class="tracking__row">
        <span class="label">예상 도착</span>
        <span data-testid="eta-time">{{ eta || '계산 중' }}</span>
        <span
          v-if="confidence"
          class="muted"
          data-testid="eta-confidence"
        >(신뢰도 {{ confidence }})</span>
      </div>

      <div
        v-if="status.droneLocation"
        class="tracking__row"
      >
        <span class="label">드론 위치</span>
        <span data-testid="drone-location">
          {{ status.droneLocation.latitude.toFixed(4) }},
          {{ status.droneLocation.longitude.toFixed(4) }}
          <template v-if="status.droneLocation.altitude">· 고도 {{ status.droneLocation.altitude }}m</template>
        </span>
      </div>

      <div class="tracking__row">
        <span class="label">갱신</span>
        <span data-testid="updated-at">{{ new Date(status.updatedAt).toLocaleTimeString('ko-KR') }}</span>
        <span
          v-if="loading"
          class="muted"
        >불러오는 중…</span>
      </div>

      <button
        v-if="cancellable"
        class="danger"
        data-testid="btn-cancel"
        @click="cancel"
      >
        예약 취소
      </button>
      <p
        v-else
        class="note"
        data-testid="cancel-unavailable"
      >
        이동을 시작한 배달은 취소할 수 없습니다.
      </p>
    </div>

    <p
      v-else-if="isPolling"
      class="note"
      data-testid="waiting-note"
    >
      배달을 준비하고 있습니다. 잠시만 기다려 주세요…
    </p>
  </section>
</template>
