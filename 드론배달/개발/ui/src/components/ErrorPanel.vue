<script setup>
import { computed } from 'vue'

const props = defineProps({
  error: { type: Object, default: null },
})

/**
 * 오류 안내.
 *
 * 사용자에게 «무엇을 하면 되는지»를 알려 준다.
 * 스택 트레이스나 내부 용어를 보여 주는 것은 안내가 아니다.
 */
const guidance = computed(() => {
  if (!props.error) return null
  if (props.error.isUserFixable) return '입력한 내용을 확인한 뒤 다시 시도해 주세요.'
  if (props.error.isRetryable) return '일시적인 문제입니다. 잠시 후 다시 시도해 주세요.'
  return '문제가 계속되면 아래 조회 번호와 함께 문의해 주세요.'
})
</script>

<template>
  <div
    v-if="error"
    class="error-panel"
    role="alert"
    data-testid="error-panel"
  >
    <p class="error-panel__message">
      {{ error.message }}
    </p>
    <p
      v-if="guidance"
      class="error-panel__guidance"
    >
      {{ guidance }}
    </p>

    <ul
      v-if="error.fieldErrors?.length"
      class="error-panel__fields"
    >
      <li
        v-for="fe in error.fieldErrors"
        :key="fe.field"
      >
        <code>{{ fe.field }}</code> — {{ fe.message }}
      </li>
    </ul>

    <p
      v-if="error.correlationId"
      class="error-panel__correlation"
    >
      조회 번호: <code data-testid="error-correlation-id">{{ error.correlationId }}</code>
    </p>
  </div>
</template>
