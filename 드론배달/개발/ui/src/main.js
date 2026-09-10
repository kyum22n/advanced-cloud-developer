import { createApp } from 'vue'
import { createRouter, createWebHistory } from 'vue-router'
import App from './App.vue'
import BookingView from './views/BookingView.vue'
import TrackingView from './views/TrackingView.vue'
import HistoryView from './views/HistoryView.vue'
import './assets/styles.css'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'booking', component: BookingView },
    { path: '/track/:deliveryId?', name: 'tracking', component: TrackingView, props: true },
    { path: '/history', name: 'history', component: HistoryView },
  ],
})

createApp(App).use(router).mount('#app')
