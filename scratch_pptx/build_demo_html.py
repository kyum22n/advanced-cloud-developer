# -*- coding: utf-8 -*-
import base64
import os

CAP_DIR = r"C:\dev\workspace-igm\advanced-cloud-developer\실습산출물\3차시\캡처"

slides = [
    {
        "file": "dev_최종점검_01_초기화면.png",
        "step": "STEP 1",
        "title": "초기 화면 — 레포 URL 입력",
        "desc": "메인 화면 접속 후 분석할 GitHub 공개 레포 URL을 입력합니다. 진입 장벽 없이 URL 하나만 필요합니다.",
    },
    {
        "file": "dev_최종점검_02_분석결과.png",
        "step": "STEP 2",
        "title": "분석 실행 → 결과 확인",
        "desc": "프로젝트 구조·아키텍처 패턴 추정·기술 스택 구성비·최근 커밋 요약이 실제 GitHub 데이터로 채워집니다. 수작업 20~30분이 수십 초로 단축됩니다.",
    },
    {
        "file": "dev_최종점검_03_Notion업로드완료.png",
        "step": "STEP 3",
        "title": "Notion 업로드 완료",
        "desc": "\"Notion에 업로드\" 버튼 클릭 한 번으로 app.notion.com에 실제 페이지가 생성되고, 업로드 완료 링크가 화면에 표시됩니다.",
    },
    {
        "file": "05_이력목록.png",
        "step": "STEP 4",
        "title": "분석 이력 목록",
        "desc": "과거에 분석한 레포 이력을 언제든 다시 조회할 수 있습니다. 성공/실패 상태와 실패 사유도 함께 기록됩니다.",
    },
]

def to_b64(fname):
    path = os.path.join(CAP_DIR, fname)
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")

slide_html = []
dot_html = []
for i, s in enumerate(slides):
    b64 = to_b64(s["file"])
    active = " active" if i == 0 else ""
    slide_html.append(f'''
    <div class="slide{active}" data-index="{i}">
      <div class="frame">
        <img src="data:image/png;base64,{b64}" alt="{s['title']}" />
      </div>
      <div class="caption">
        <span class="step">{s['step']}</span>
        <h2>{s['title']}</h2>
        <p>{s['desc']}</p>
      </div>
    </div>''')
    dot_html.append(f'<button class="dot{" active" if i==0 else ""}" data-index="{i}" aria-label="{s["step"]}"></button>')

html = f"""<!doctype html><title>레포 인사이트 시연</title>
<style>
:root {{
  --bg: #f4f6fb;
  --surface: #ffffff;
  --ink: #16324f;
  --ink-soft: #4a5b72;
  --line: #dbe3f0;
  --accent: #2f6fb3;
  --accent-soft: #cadcfc;
  --navy: #1e2761;
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
    --bg: #0f1526;
    --surface: #161d33;
    --ink: #e8edf9;
    --ink-soft: #a9b6d0;
    --line: #2a3352;
    --accent: #7fb0e8;
    --accent-soft: #26345c;
    --navy: #cadcfc;
  }}
}}
:root[data-theme="dark"] {{
  --bg: #0f1526;
  --surface: #161d33;
  --ink: #e8edf9;
  --ink-soft: #a9b6d0;
  --line: #2a3352;
  --accent: #7fb0e8;
  --accent-soft: #26345c;
  --navy: #cadcfc;
}}
* {{ box-sizing: border-box; }}
body {{
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font-family: "Pretendard", "Noto Sans KR", "Malgun Gothic", -apple-system, sans-serif;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 2.5rem 1.25rem 3rem;
  gap: 1.5rem;
  min-height: 100vh;
}}
header {{ text-align: center; max-width: 720px; }}
.eyebrow {{
  font-size: 0.75rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--accent);
  font-weight: 600;
}}
h1 {{
  font-size: clamp(1.4rem, 2.6vw, 1.9rem);
  margin: 0.35rem 0 0.5rem;
  text-wrap: balance;
}}
header p {{ color: var(--ink-soft); font-size: 0.95rem; margin: 0; }}

.stage {{
  position: relative;
  width: min(880px, 100%);
  background: var(--surface);
  border: 1px solid var(--line);
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 12px 32px -18px rgba(30, 39, 97, 0.35);
}}
.slides {{ position: relative; min-height: 420px; }}
.slide {{
  display: none;
  flex-direction: column;
}}
.slide.active {{ display: flex; }}
.frame {{
  background: var(--navy);
  padding: 1.1rem;
  display: flex;
  justify-content: center;
}}
.frame img {{
  max-width: 100%;
  border-radius: 8px;
  box-shadow: 0 8px 24px -8px rgba(0,0,0,0.4);
  display: block;
}}
.caption {{
  padding: 1.25rem 1.5rem 1.5rem;
  border-top: 1px solid var(--line);
}}
.step {{
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.1em;
  color: var(--accent);
}}
.caption h2 {{
  font-size: 1.15rem;
  margin: 0.3rem 0 0.4rem;
}}
.caption p {{
  margin: 0;
  color: var(--ink-soft);
  font-size: 0.92rem;
  line-height: 1.55;
  max-width: 62ch;
}}

.controls {{
  display: flex;
  align-items: center;
  gap: 1rem;
}}
.dots {{ display: flex; gap: 0.5rem; }}
.dot {{
  width: 9px; height: 9px; border-radius: 50%;
  border: none; background: var(--line);
  cursor: pointer; padding: 0;
}}
.dot.active {{ background: var(--accent); width: 22px; border-radius: 5px; transition: width .2s ease; }}
.navbtn {{
  border: 1px solid var(--line);
  background: var(--surface);
  color: var(--ink);
  border-radius: 999px;
  width: 34px; height: 34px;
  font-size: 1rem;
  cursor: pointer;
  display: flex; align-items: center; justify-content: center;
}}
.navbtn:hover {{ border-color: var(--accent); color: var(--accent); }}
.navbtn:focus-visible, .dot:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}

footer {{ color: var(--ink-soft); font-size: 0.78rem; }}
</style>

<header>
  <div class="eyebrow">Demo Walkthrough</div>
  <h1>레포 인사이트 · GitHub → Notion 포트폴리오 리포트 도구</h1>
  <p>dev 환경(k3d, http://localhost:8080)에서 실제로 실행한 화면을 순서대로 재생합니다.</p>
</header>

<div class="stage">
  <div class="slides">
    {''.join(slide_html)}
  </div>
</div>

<div class="controls">
  <button class="navbtn" id="prev" aria-label="이전">‹</button>
  <div class="dots">{''.join(dot_html)}</div>
  <button class="navbtn" id="next" aria-label="다음">›</button>
</div>

<footer>facebook/react 레포 분석 실사용 예시 · 자동 재생 (4초 간격, 마우스를 올리면 일시정지)</footer>

<script>
const slides = document.querySelectorAll('.slide');
const dots = document.querySelectorAll('.dot');
let idx = 0;
let timer;

function show(i) {{
  idx = (i + slides.length) % slides.length;
  slides.forEach((s, n) => s.classList.toggle('active', n === idx));
  dots.forEach((d, n) => d.classList.toggle('active', n === idx));
}}

function next() {{ show(idx + 1); }}
function prev() {{ show(idx - 1); }}

function startAuto() {{
  stopAuto();
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {{
    timer = setInterval(next, 4000);
  }}
}}
function stopAuto() {{ if (timer) clearInterval(timer); }}

document.getElementById('next').addEventListener('click', () => {{ next(); startAuto(); }});
document.getElementById('prev').addEventListener('click', () => {{ prev(); startAuto(); }});
dots.forEach((d, n) => d.addEventListener('click', () => {{ show(n); startAuto(); }}));

const stage = document.querySelector('.stage');
stage.addEventListener('mouseenter', stopAuto);
stage.addEventListener('mouseleave', startAuto);

startAuto();
</script>
"""

out_path = r"C:\dev\workspace-igm\advanced-cloud-developer\scratch_pptx\demo.html"
with open(out_path, "w", encoding="utf-8") as f:
    f.write(html)
print("wrote", out_path, len(html))
