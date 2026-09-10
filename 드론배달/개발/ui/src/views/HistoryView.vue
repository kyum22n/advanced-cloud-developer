<script setup>
import { ref } from 'vue'
import { api } from '../api/client.js'
import StatusBadge from '../components/StatusBadge.vue'
import ErrorPanel from '../components/ErrorPanel.vue'

const deliveryId = ref('')
const entry = ref(null)
const error = ref(null)
const loading = ref(false)

async function lookup() {
  loading.value = true
  error.value = null
  entry.value = null
  try {
    entry.value = await api.getHistory(deliveryId.value)
  } catch (e) {
    error.value = e
  } finally {
    loading.value = false
  }
}

function duration(seconds) {
  if (seconds == null || seconds < 0) return '진행 중'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return m > 0 ? `${m}분 ${s}초` : `${s}초`
}
</script>

<template>
  <section class="card">
    <h2>배달 이력</h2>

    <form
      class="inline-form"
      data-testid="history-form"
      @submit.prevent="lookup"
    >
      <input
        v-model="deliveryId"
        placeholder="배달 번호"
        data-testid="input-history-id"
        required
      >
      <button
        type="submit"
        :disabled="loading"
        data-testid="btn-lookup"
      >
        {{ loading ? '조회 중…' : '조회' }}
      </button>
    </form>

    <ErrorPanel :error="error" />

    <div
      v-if="entry"
      class="history"
      data-testid="history-panel"
    >
      <div class="tracking__row">
        <span class="label">최종 상태</span>
        <StatusBadge :status="entry.finalStatus" />
      </div>
      <div class="tracking__row">
        <span class="label">소요 시간</span>
        <span data-testid="history-duration">{{ duration(entry.durationSeconds) }}</span>
      </div>
      <div
        v-if="entry.droneId"
        class="tracking__row"
      >
        <span class="label">드론</span>
        <span data-testid="history-drone">{{ entry.droneId }}</span>
      </div>
      <div
        v-if="entry.failureReason"
        class="tracking__row"
      >
        <span class="label">실패 사유</span>
        <span data-testid="history-failure">{{ entry.failureReason }}</span>
      </div>

      <h3>진행 이력</h3>
      <ol
        class="timeline"
        data-testid="history-timeline"
      >
        <li
          v-for="m in entry.milestones"
          :key="m.eventType"
        >
          <span class="timeline__time">
            {{ new Date(m.occurredAt).toLocaleString('ko-KR') }}
          </span>
          <span class="timeline__event">{{ m.eventType }}</span>
        </li>
      </ol>
    </div>
  </section>
</template>
