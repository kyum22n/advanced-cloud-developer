<script setup>
defineProps({
  items: { type: Array, required: true },
});

function formatAmount(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n.toLocaleString('ko-KR') : String(value);
}
</script>

<template>
  <p
    v-if="items.length === 0"
    class="empty"
    data-testid="empty-message"
  >
    등록된 항목이 없습니다.
  </p>
  <table
    v-else
    data-testid="item-table"
  >
    <thead>
      <tr>
        <th>ID</th><th>제목</th><th>금액</th><th>생성 시각</th>
      </tr>
    </thead>
    <tbody data-testid="item-tbody">
      <tr
        v-for="item in items"
        :key="item.id"
        data-testid="item-row"
      >
        <td>{{ item.id }}</td>
        <td>{{ item.title }}</td>
        <td>{{ formatAmount(item.amount) }}</td>
        <td>{{ item.createdAt }}</td>
      </tr>
    </tbody>
  </table>
</template>
