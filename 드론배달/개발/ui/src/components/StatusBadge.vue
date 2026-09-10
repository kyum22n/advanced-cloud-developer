<script setup>
import { computed } from 'vue'

const props = defineProps({
  status: { type: String, default: null },
})

/** 상태별 색과 한국어 표기 — 상태 문자열이 화면에 그대로 나오면 안 된다. */
const STATUS_MAP = {
  PENDING:            { label: '접수됨',        tone: 'wait' },
  SCHEDULED:          { label: '드론 배정됨',   tone: 'info' },
  DELEGATED:          { label: '타사 위탁',     tone: 'info' },
  IN_TRANSIT:         { label: '픽업 완료',     tone: 'active' },
  HEADED_TO_DROPOFF:  { label: '배달 중',       tone: 'active' },
  COMPLETED:          { label: '배달 완료',     tone: 'done' },
  CANCELLED:          { label: '취소됨',        tone: 'muted' },
  FAILED:             { label: '실패',          tone: 'error' },
  COMPENSATED:        { label: '실패(정리됨)',  tone: 'error' },
}

const view = computed(() => STATUS_MAP[props.status] || { label: props.status || '—', tone: 'muted' })
</script>

<template>
  <span
    :class="['badge', `badge--${view.tone}`]"
    data-testid="status-badge"
  >
    {{ view.label }}
  </span>
</template>
