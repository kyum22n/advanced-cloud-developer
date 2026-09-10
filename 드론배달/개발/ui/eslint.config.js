import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'

export default [
  // 빌드 산출물과 의존성은 검사하지 않는다 — 우리가 쓴 코드가 아니다.
  { ignores: ['dist/**', 'node_modules/**', 'coverage/**'] },
  js.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: {
        fetch: 'readonly',
        document: 'readonly',
        window: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        globalThis: 'readonly',
        crypto: 'readonly',
        URLSearchParams: 'readonly',
      },
    },
    rules: {
      'no-console': ['error', { allow: ['warn', 'error'] }],
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'vue/multi-word-component-names': 'off',
    },
  },
]
