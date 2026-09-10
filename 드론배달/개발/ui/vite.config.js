import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  build: {
    // 파일명에 해시를 넣어 자산은 1년 캐시하고 index.html 만 no-cache 로 둔다.
    // (설계/05_API_게이트웨이_설계서.md §7)
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },
  server: {
    proxy: {
      // 개발 중에는 게이트웨이 대신 로컬 서비스로 직접 보낸다.
      '/api/v1/deliveries': { target: 'http://localhost:8081', changeOrigin: true },
      '/api/v1/history': { target: 'http://localhost:8086', changeOrigin: true },
    },
  },
  test: {
    environment: 'jsdom',
    // Windows 에서 기본 스레드 풀이 워커를 종료할 때 EPERM 을 낸다.
    // 포크 풀 단일 프로세스로 두면 재현 가능하게 동작한다.
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } },
  },
})
