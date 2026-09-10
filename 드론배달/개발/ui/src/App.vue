<script setup>
import { RouterLink, RouterView } from 'vue-router'
</script>

<template>
  <div class="app">
    <header class="app-header">
      <h1 class="brand">
        🚁 Fabrikam 드론 배달
      </h1>
      <nav>
        <RouterLink
          to="/"
          data-testid="nav-booking"
        >
          예약
        </RouterLink>
        <RouterLink
          to="/track"
          data-testid="nav-tracking"
        >
          추적
        </RouterLink>
        <RouterLink
          to="/history"
          data-testid="nav-history"
        >
          이력
        </RouterLink>
      </nav>
    </header>

    <main class="app-main">
      <RouterView />
    </main>

    <footer class="app-footer">
      <p>실습용 가상 시스템입니다. 실제 개인정보를 입력하지 마세요.</p>
    </footer>
  </div>
</template>
