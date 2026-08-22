<script setup>
defineProps({
  weeks: { type: Array, required: true },
});

function formatAmount(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n.toLocaleString('ko-KR') : String(value);
}
</script>

<template>
  <table data-testid="summary-table">
    <thead>
      <tr>
        <th>주차</th><th>건수</th><th>합계</th>
      </tr>
    </thead>
    <tbody data-testid="summary-tbody">
      <tr
        v-for="week in weeks"
        :key="week.week"
        data-testid="summary-row"
      >
        <td>{{ week.week }}</td>
        <td>{{ week.count }}</td>
        <td>{{ formatAmount(week.amount) }}</td>
      </tr>
    </tbody>
  </table>
</template>
