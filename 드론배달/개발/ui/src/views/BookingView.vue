<script setup>
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../api/client.js'
import ErrorPanel from '../components/ErrorPanel.vue'

const router = useRouter()

// 서울 시내 가상 좌표 — 실제 주소를 쓰지 않는다 (실습 안전 수칙).
const form = reactive({
  ownerId: 'acc-0001',
  pickupLat: 37.5665,
  pickupLng: 126.978,
  dropoffLat: 37.5172,
  dropoffLng: 127.0473,
  weight: 2.5,
  unit: 'KG',
  size: 'SMALL',
  description: '서류 봉투',
  earliestMinutes: 10,
  latestMinutes: 60,
})

const submitting = ref(false)
const error = ref(null)
const accepted = ref(null)

async function submit() {
  submitting.value = true
  error.value = null
  accepted.value = null

  const now = Date.now()
  try {
    accepted.value = await api.createDelivery({
      ownerId: form.ownerId,
      pickup: { latitude: Number(form.pickupLat), longitude: Number(form.pickupLng), altitude: 0 },
      dropoff: { latitude: Number(form.dropoffLat), longitude: Number(form.dropoffLng), altitude: 0 },
      pickupWindow: {
        earliest: new Date(now + form.earliestMinutes * 60_000).toISOString(),
        latest: new Date(now + form.latestMinutes * 60_000).toISOString(),
      },
      packageInfo: {
        weight: Number(form.weight),
        unit: form.unit,
        size: form.size,
        description: form.description,
      },
    })
  } catch (e) {
    error.value = e
  } finally {
    submitting.value = false
  }
}

function goTrack() {
  router.push({ name: 'tracking', params: { deliveryId: accepted.value.deliveryId } })
}
</script>

<template>
  <section class="card">
    <h2>배달 예약</h2>

    <form
      class="form"
      data-testid="booking-form"
      @submit.prevent="submit"
    >
      <label>
        계정 ID
        <input
          v-model="form.ownerId"
          data-testid="input-owner"
          required
        >
      </label>

      <fieldset>
        <legend>픽업 위치</legend>
        <label>위도 <input
          v-model="form.pickupLat"
          type="number"
          step="0.0001"
          data-testid="input-pickup-lat"
          required
        ></label>
        <label>경도 <input
          v-model="form.pickupLng"
          type="number"
          step="0.0001"
          data-testid="input-pickup-lng"
          required
        ></label>
      </fieldset>

      <fieldset>
        <legend>배달 위치</legend>
        <label>위도 <input
          v-model="form.dropoffLat"
          type="number"
          step="0.0001"
          data-testid="input-dropoff-lat"
          required
        ></label>
        <label>경도 <input
          v-model="form.dropoffLng"
          type="number"
          step="0.0001"
          data-testid="input-dropoff-lng"
          required
        ></label>
      </fieldset>

      <fieldset>
        <legend>패키지</legend>
        <label>무게 <input
          v-model="form.weight"
          type="number"
          step="0.1"
          min="0.001"
          data-testid="input-weight"
          required
        ></label>
        <label>
          단위
          <select
            v-model="form.unit"
            data-testid="select-unit"
          >
            <option value="KG">kg</option>
            <option value="G">g</option>
          </select>
        </label>
        <label>
          크기
          <select
            v-model="form.size"
            data-testid="select-size"
          >
            <option value="SMALL">소형</option>
            <option value="MEDIUM">중형</option>
            <option value="LARGE">대형 (드론 불가)</option>
          </select>
        </label>
        <label>설명 <input
          v-model="form.description"
          maxlength="200"
          data-testid="input-description"
        ></label>
      </fieldset>

      <button
        type="submit"
        :disabled="submitting"
        data-testid="btn-submit"
      >
        {{ submitting ? '접수 중…' : '배달 예약' }}
      </button>
    </form>

    <ErrorPanel :error="error" />

    <div
      v-if="accepted"
      class="accepted"
      data-testid="accepted-panel"
    >
      <h3>접수되었습니다</h3>
      <p>
        배달 번호 <strong data-testid="accepted-delivery-id">{{ accepted.deliveryId }}</strong>
      </p>
      <p class="note">
        아직 처리 중입니다. 배정까지 잠시 걸릴 수 있습니다.
      </p>
      <button
        data-testid="btn-go-track"
        @click="goTrack"
      >
        추적 화면으로
      </button>
    </div>
  </section>
</template>
