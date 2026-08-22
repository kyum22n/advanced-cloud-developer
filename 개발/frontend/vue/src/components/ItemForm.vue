<script setup>
import { ref } from 'vue';

const emit = defineEmits(['submit']);
const title = ref('');
const amount = ref('0');

function onSubmit() {
  emit('submit', { title: title.value, amount: amount.value });
  title.value = '';
  amount.value = '0';
}
</script>

<template>
  <form
    data-testid="create-form"
    novalidate
    @submit.prevent="onSubmit"
  >
    <label for="title">제목</label>
    <input
      id="title"
      v-model="title"
      data-testid="input-title"
      maxlength="200"
    >

    <label for="amount">금액</label>
    <input
      id="amount"
      v-model="amount"
      data-testid="input-amount"
      inputmode="decimal"
    >

    <button
      type="submit"
      data-testid="btn-submit"
    >
      등록
    </button>
  </form>
</template>
