import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import StatusBadge from './StatusBadge.vue'

describe('StatusBadge', () => {
  it('상태 코드를 한국어로 보여 준다 — 사용자에게 HEADED_TO_DROPOFF 를 보이면 안 된다', () => {
    const w = mount(StatusBadge, { props: { status: 'HEADED_TO_DROPOFF' } })
    expect(w.text()).toBe('배달 중')
  })

  it('알 수 없는 상태도 화면을 깨뜨리지 않는다 — 새 상태가 추가돼도 견딘다', () => {
    const w = mount(StatusBadge, { props: { status: 'SOME_NEW_STATUS' } })
    expect(w.text()).toBe('SOME_NEW_STATUS')
  })

  it('상태가 없으면 대시를 보여 준다', () => {
    const w = mount(StatusBadge, { props: { status: null } })
    expect(w.text()).toBe('—')
  })

  it('완료 상태는 성공 색을 쓴다', () => {
    const w = mount(StatusBadge, { props: { status: 'COMPLETED' } })
    expect(w.classes()).toContain('badge--done')
  })

  it('실패 상태는 오류 색을 쓴다', () => {
    const w = mount(StatusBadge, { props: { status: 'FAILED' } })
    expect(w.classes()).toContain('badge--error')
  })
})
