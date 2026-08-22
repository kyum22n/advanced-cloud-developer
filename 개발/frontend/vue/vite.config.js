import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// dev 에서는 백엔드를 프록시로 붙인다 — stg·prd 는 Ingress 가 같은 오리진으로 묶는다
export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    proxy: {
      '/api': { target: 'http://localhost:8080', changeOrigin: true },
      '/version': { target: 'http://localhost:8080', changeOrigin: true },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
});
