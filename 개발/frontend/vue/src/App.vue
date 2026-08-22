<script setup>
import { onMounted, ref } from 'vue';
import { createItem, fetchItems, fetchSummary, fetchVersion } from './api';
import ItemForm from './components/ItemForm.vue';
import ItemTable from './components/ItemTable.vue';
import SummaryTable from './components/SummaryTable.vue';

const env = ref('-');
const version = ref('-');
const items = ref([]);
const weeks = ref([]);
const errorMessage = ref('');

async function refresh() {
  const [list, summary] = await Promise.all([fetchItems(), fetchSummary()]);
  items.value = list.items ?? [];
  weeks.value = summary.weeks ?? [];
}

async function onCreate({ title, amount }) {
  errorMessage.value = '';
  try {
    await createItem(title, amount);
    await refresh();
  } catch (e) {
    errorMessage.value = e.message;
  }
}

onMounted(async () => {
  try {
    const v = await fetchVersion();
    env.value = v.env ?? '-';
    version.value = v.version ?? '-';
    await refresh();
  } catch (e) {
    errorMessage.value = e.message;
  }
});
</script>

<template>
  <header class="topbar">
    <h1>나만의 업무 앱</h1>
    <span
      class="env"
      data-testid="env-badge"
    >{{ env }}</span>
    <span
      class="ver"
      data-testid="version-badge"
    >{{ version }}</span>
  </header>

  <main>
    <section class="panel">
      <h2>항목 등록</h2>
      <ItemForm @submit="onCreate" />
      <p
        v-if="errorMessage"
        class="error"
        data-testid="error-message"
        role="alert"
      >
        {{ errorMessage }}
      </p>
    </section>

    <section class="panel">
      <h2>항목 목록</h2>
      <ItemTable :items="items" />
    </section>

    <section class="panel">
      <h2>주차별 집계</h2>
      <SummaryTable :weeks="weeks" />
    </section>
  </main>
</template>
