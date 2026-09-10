# 개발 — 데이터 생성 · 파이프라인 · 검색

> 설계([../설계/](../설계/))를 코드로 옮긴 결과입니다. 각 파일의 «왜»는 코드 주석에 있습니다.

---

## 1. 구조

```
개발/
├── generator/                  가상 코퍼스 생성
│   ├── taxonomy.py             택소노미 · 어휘 · 동의어 · 함정 정의
│   ├── generate_corpus.py      코퍼스 생성기
│   └── korean.py               ★ 한국어 조사 처리 (13/13 테스트 통과)
│
├── data/                       생성 산출물
│   ├── corpus.jsonl            문서 11,021건 (2.87 MB)
│   ├── chunks.jsonl            청크 12,863건
│   ├── vectors.npz             벡터 12,863 × 256 (로컬 LSA)
│   ├── traps.json              함정 정답 키 34건
│   └── *_stats.json            통계
│
├── pipeline/
│   ├── chunker.py              문서 유형별 청킹
│   └── embed.py                임베딩 (Azure / 로컬 LSA) + 비용 추정
│
├── search/
│   ├── hybrid.py               BM25 + 벡터 + RRF + 재순위 + 권위 가중
│   └── agentic.py              쿼리 분해 + 병렬 + 합성
│
├── config/                     Azure 배포 산출물
│   ├── build_azure_config.py   JSON 생성
│   ├── deploy_index.py         배포 (⚠️ 확인 프롬프트 필수)
│   ├── index.json              인덱스 스키마 (21 필드)
│   ├── skillset.json           SplitSkill + EmbeddingSkill
│   ├── datasource.json · indexer.json
│   ├── knowledge_source.json · knowledge_base.{dev,stg,prd}.json
│   └── .env.example            ⚠️ 주소만. 비밀 없음
│
└── playground/
    └── 시연_시나리오.md         Foundry 플레이그라운드 7막 시연
```

---

## 2. 실행 순서

```bash
# ① 코퍼스 생성 (11,021 문서)
python generator/generate_corpus.py --seed 20260829

# ② 청킹 (12,863 청크)
python pipeline/chunker.py --target 800 --max 1200 --overlap 120

# ③ 비용 추정  ★ 여기서 멈춰 규모를 확인한다
python pipeline/embed.py --estimate-only

# ④ 임베딩 (오프라인 검증용)
python pipeline/embed.py --backend local-lsa --dim 256

# ⑤ 검색 확인
python search/hybrid.py --q "연차휴가 일수 기준 며칠" --mode compare
python search/agentic.py --q "3년차 개발직이 육아휴직 쓰면 급여와 평가는" --compare

# ⑥ Azure 구성 생성 (파일만 만든다. 배포하지 않는다)
python config/build_azure_config.py --env dev

# ⑦ 배포 계획 확인
python config/deploy_index.py --env dev --dry-run
```

---

## 3. 실행 결과 (실측)

### 3.1 코퍼스

| 항목 | 값 |
| --- | ---: |
| **문서 수** | **11,021** ✅ (목표 1만 건 초과) |
| 총 문자 수 | 2,871,751 |
| 길이 최소/중앙/최대 | 73 / 204 / **8,203**자 |
| 중분류 · 세부주제 | 24 · 165 |
| 미해결 조사 표기 | **0건** ✅ |

| 문서 유형 | 건수 | | 상태 | 건수 | | 보안등급 | 건수 |
| --- | ---: | --- | --- | ---: | --- | --- | ---: |
| 문의이력 | 4,000 | | 현행 | 9,721 | | 사내 | 7,375 |
| FAQ | 3,600 | | 폐지 | 1,048 | | 공개 | 3,314 |
| 공지 | 1,200 | | 개정예정 | 252 | | 제한 | 332 |
| 안내서 | 905 | | | | | | |
| 규정 | 527 | | | | | | |
| 서식안내 | 400 | | | | | | |
| 매뉴얼 | 220 | | | | | | |
| 지침 | 149 | | | | | | |
| 규정전문 | 20 | | | | | | |

### 3.2 청킹

| 항목 | 값 |
| --- | ---: |
| 문서 → 청크 | 11,021 → **12,863** (배율 1.17) |
| 청크 자수 중앙/p90/최대 | 250 / 466 / **1,199** |
| **상한(1,200자) 초과** | **0건** ✅ |
| 분할 파편 | 244건 |
| 짧은 원자 청크 | 466건 (완결된 FAQ — 정상) |

유형별 배율 — **매뉴얼 8.00 · 규정전문 16.10 · 나머지 1.00**

### 3.3 임베딩

| 항목 | 값 |
| --- | ---: |
| **총 토큰 (추정)** | **3,117,319** |
| 청크당 평균/최대 | 242 / 1,261 |
| 모델 한계(8,191) 초과 | **0건** ✅ |
| 벡터 | 12,863 × 256 (로컬 LSA) |

### 3.4 검색 품질 → [테스트/](../테스트/README.md)

---

## 4. 핵심 코드 위치

| 개념 | 파일 |
| --- | --- |
| 택소노미 5축 · 동의어 · 함정 | [`generator/taxonomy.py`](generator/taxonomy.py) |
| **질문 의도 ↔ 답변 매칭** | [`generator/taxonomy.py`](generator/taxonomy.py) `INTENT_ANSWERS` |
| **한국어 조사 처리** | [`generator/korean.py`](generator/korean.py) |
| 함정 34건 심기 | [`generator/generate_corpus.py`](generator/generate_corpus.py) `gen_traps` |
| **문서 유형별 청킹** | [`pipeline/chunker.py`](pipeline/chunker.py) `ATOMIC_DOC_TYPES` |
| 제목 머리말 예산 처리 | [`pipeline/chunker.py`](pipeline/chunker.py) `prefix_len` |
| 비용 추정 (단가 «확인 필요») | [`pipeline/embed.py`](pipeline/embed.py) `MODELS` |
| 로컬 LSA (numpy 만) | [`pipeline/embed.py`](pipeline/embed.py) `build_local_lsa` |
| **RRF (k=60)** | [`search/hybrid.py`](search/hybrid.py) `reciprocal_rank_fusion` |
| **IDF 가중 재순위** | [`search/hybrid.py`](search/hybrid.py) `naive_rerank` |
| **보안 필터 강제** | [`search/hybrid.py`](search/hybrid.py) `apply_filter` |
| 쿼리 분해 | [`search/agentic.py`](search/agentic.py) `plan_queries` |
| Azure 지식 베이스 호출 | [`search/agentic.py`](search/agentic.py) `AzureAgenticSearch` |

---

## 5. ⚠️ 대체물로 검증한 것 — 한계를 명시

| 실제 | 이 프로젝트 | 한계 |
| --- | --- | --- |
| Azure OpenAI 임베딩 | **로컬 LSA** (TF‑IDF + SVD) | 외부 지식 없음. «법카 ↔ 법인카드»를 모른다 |
| Azure 시맨틱 랭커 | **IDF 가중 근사** | 학습된 교차 인코더가 아니다 |
| LLM 쿼리 분해 | **규칙 기반** | 표현이 예상 밖이면 분해 못 한다 |

> 이 대체물로 잰 수치는 **«전략 간 상대 비교»** 에 쓰고,
> **«운영 품질의 절대 예측»** 에는 쓰지 않습니다.
> 각 파일 상단 독스트링에 같은 경고를 적어 두었습니다.

---

## 6. 실행하지 않은 것

| 항목 | 이유 |
| --- | --- |
| Azure 실제 배포 | 구독·과금은 별도 판단 (CON‑07) |
| Azure OpenAI 임베딩 호출 | 과금 |
| 채팅 모델 호출 (생성 단계) | 과금 · 자격 증명 |
| 플레이그라운드 시연 | 배포 선행 필요 |

`deploy_index.py` 는 **`--dry-run` 으로만 실행**했고, 실제 배포에는
정확히 `yes` 를 입력해야 진행됩니다.

---

## 7. 재현

```bash
python generator/generate_corpus.py --seed 20260829
```

같은 시드는 같은 코퍼스를 만듭니다. 실험 비교의 전제입니다.

---

## 8. 설계 문서와의 대응

| 구현 | 근거 설계서 |
| --- | --- |
| 택소노미 · 함정 | [분석/02](../분석/02_도메인_지식체계_분석.md) · [분석/04](../분석/04_데이터_소스_분석.md) |
| 인덱스 스키마 | [설계/03](../설계/03_데이터_모델_및_인덱스_설계서.md) |
| 청킹 파라미터 | [설계/04](../설계/04_청킹_전략_설계서.md) |
| 임베딩 · 비용 | [설계/05](../설계/05_임베딩_전략_설계서.md) |
| RRF · 권위 가중 | [설계/06](../설계/06_Hybrid_검색_설계서.md) |
| 쿼리 분해 | [설계/07](../설계/07_Agentic_검색_설계서.md) |
| 시스템 프롬프트 | [설계/08](../설계/08_프롬프트_및_응답_설계서.md) |
| 보안 필터 | [설계/10](../설계/10_보안_및_거버넌스_설계서.md) |
