# -*- coding: utf-8 -*-
"""Azure AI Search 배포 산출물 생성 — 인덱스 · 기술 세트 · 지식 원본 · 지식 베이스.

왜 «코드로» 만드는가
    포털에서 클릭으로 만들면 재현할 수 없고, 무엇이 왜 그렇게 설정됐는지 남지 않는다.
    JSON 을 생성하는 스크립트로 두면
      · 청킹 파라미터가 로컬 실험 결과(chunk_stats.json)와 «같은 값»임을 보장하고
      · 환경(dev/prd)별 차이를 변수 하나로 관리하며
      · 변경 이력이 Git 에 남는다

⚠️ 이 스크립트는 «파일만» 만든다. Azure 에 아무것도 배포하지 않는다.
   배포는 deploy_index.py 가 담당하며, 사람이 명시적으로 실행해야 한다.

API 버전 (2026-08 기준)
    2026-04-01          일반 공급(GA). 에이전트 검색의 상당 부분이 여기에 포함된다.
    2026-05-01-preview  검색 추론 노력(retrievalReasoningEffort) 등 일부 기능은 아직 미리 보기.
    ⚠️ 미리 보기 기능은 SLA 가 없다. 운영 도입 전에 GA 여부를 다시 확인할 것.

사용:
    python build_azure_config.py --env dev
"""
import argparse
import io
import json
import os
import sys

if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

API_GA = "2026-04-01"
API_PREVIEW = "2026-05-01-preview"

INDEX_NAME = "hr-ga-chunks"
PARENT_INDEX_NAME = "hr-ga-docs"
SKILLSET_NAME = "hr-ga-skillset"
DATASOURCE_NAME = "hr-ga-blob"
INDEXER_NAME = "hr-ga-indexer"
KNOWLEDGE_SOURCE_NAME = "hr-ga-knowledge-source"
KNOWLEDGE_BASE_NAME = "hr-ga-knowledge-base"

EMBEDDING_MODEL = "text-embedding-3-large"
EMBEDDING_DIM = 1536      # MRL 축소. 3072 대비 저장·연산 비용이 절반이고 품질 손실은 작다


# ═══════════════════════════════════════════════════════════ 인덱스

def build_index(chunk_stats):
    """청크 인덱스 스키마.

    필드 설계 원칙
      · searchable  BM25 대상. 한국어 분석기를 지정해야 형태소 단위로 쪼개진다.
      · filterable  필터·보안 강제에 쓴다. 분석되지 않으므로 정확히 일치해야 한다.
      · facetable   집계(팩싯) 대상. filterable 과 별개 비용이 든다.
      · retrievable 응답에 포함할지. 벡터는 false 로 두어 응답 크기를 줄인다.
      · sortable    정렬. 필요 없는 필드에 켜면 인덱스만 커진다.
    """
    return {
        "name": INDEX_NAME,
        "@odata.etag": None,
        "fields": [
            # ── 키
            {
                "name": "chunk_id", "type": "Edm.String",
                "key": True, "searchable": False, "filterable": True,
                "sortable": True, "facetable": False, "retrievable": True,
            },
            # ── 부모 문서 — 청크에서 원문으로 되돌아가는 열쇠
            {
                "name": "parent_id", "type": "Edm.String",
                "searchable": False, "filterable": True, "facetable": False,
                "retrievable": True,
                # ⚠️ 인덱스 프로젝션이 부모-자식을 연결할 때 이 필드를 쓴다
            },
            {
                "name": "chunk_index", "type": "Edm.Int32",
                "searchable": False, "filterable": True, "sortable": True,
                "retrievable": True,
            },

            # ── 본문 (BM25 + 시맨틱 랭커 대상)
            {
                "name": "title", "type": "Edm.String",
                "searchable": True, "filterable": False, "retrievable": True,
                # ★ 한국어 분석기. 지정하지 않으면 standard 분석기가 쓰여
                #   «연차휴가를»과 «연차휴가는»이 다른 토큰이 된다.
                "analyzer": "ko.microsoft",
            },
            {
                "name": "content", "type": "Edm.String",
                "searchable": True, "filterable": False, "retrievable": True,
                "analyzer": "ko.microsoft",
            },

            # ── 벡터
            {
                "name": "content_vector", "type": "Collection(Edm.Single)",
                "searchable": True, "filterable": False, "sortable": False,
                "facetable": False,
                # ★ 응답에 벡터를 담지 않는다. 1536개 float × 50건 = 응답 수 MB.
                "retrievable": False,
                "dimensions": EMBEDDING_DIM,
                "vectorSearchProfile": "hnsw-profile",
            },

            # ── 분류 (필터 · 팩싯)
            {"name": "category", "type": "Edm.String",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},
            {"name": "subcategory", "type": "Edm.String",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},
            {"name": "topic", "type": "Edm.String",
             "searchable": True, "filterable": True, "facetable": True,
             "retrievable": True, "analyzer": "ko.microsoft"},
            {"name": "doc_type", "type": "Edm.String",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},
            {"name": "doc_group", "type": "Edm.String",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},

            # ── 수명 주기 — «폐지된 규정»을 걸러내는 핵심 필드
            {"name": "status", "type": "Edm.String",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},
            {"name": "version", "type": "Edm.String",
             "searchable": False, "filterable": True, "retrievable": True},
            {"name": "effective_date", "type": "Edm.DateTimeOffset",
             "searchable": False, "filterable": True, "sortable": True, "retrievable": True},
            {"name": "expiry_date", "type": "Edm.DateTimeOffset",
             "searchable": False, "filterable": True, "sortable": True, "retrievable": True},
            {"name": "updated_at", "type": "Edm.DateTimeOffset",
             "searchable": False, "filterable": True, "sortable": True, "retrievable": True},

            # ── 접근 제어
            #    ★ 이 필드가 «보안»의 실체다. LLM 프롬프트로 «제한 문서는 보여 주지 마»라고
            #      지시하는 것은 방어가 아니다. 검색 단계에서 필터로 배제해야 한다.
            {"name": "security_level", "type": "Edm.String",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},
            {"name": "audience", "type": "Collection(Edm.String)",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},
            {"name": "owner_dept", "type": "Edm.String",
             "searchable": False, "filterable": True, "facetable": True, "retrievable": True},

            # ── 보조
            {"name": "keywords", "type": "Collection(Edm.String)",
             "searchable": True, "filterable": True, "facetable": True,
             "retrievable": True, "analyzer": "ko.microsoft"},
            {"name": "source_uri", "type": "Edm.String",
             "searchable": False, "filterable": False, "retrievable": True},
        ],

        # ── 벡터 검색 구성
        "vectorSearch": {
            "algorithms": [{
                "name": "hnsw-config",
                "kind": "hnsw",
                "hnswParameters": {
                    # m: 노드당 연결 수. 크면 재현율↑ 메모리↑
                    "m": 4,
                    # 색인 시 탐색 폭. 크면 그래프 품질↑ 색인 시간↑
                    "efConstruction": 400,
                    # 검색 시 탐색 폭. 크면 재현율↑ 지연↑
                    "efSearch": 500,
                    "metric": "cosine",
                },
            }],
            "profiles": [{
                "name": "hnsw-profile",
                "algorithm": "hnsw-config",
                # ★ 벡터라이저를 프로필에 붙여야 «쿼리 시 자동 벡터화»가 된다.
                #   없으면 클라이언트가 직접 임베딩을 만들어 보내야 한다.
                "vectorizer": "openai-vectorizer",
            }],
            "vectorizers": [{
                "name": "openai-vectorizer",
                "kind": "azureOpenAI",
                "azureOpenAIParameters": {
                    "resourceUri": "https://{AZURE_OPENAI_RESOURCE}.openai.azure.com",
                    "deploymentId": "{EMBEDDING_DEPLOYMENT}",
                    "modelName": EMBEDDING_MODEL,
                    # ⚠️ apiKey 를 쓰지 않는다. 검색 서비스의 관리 ID 로 인증한다.
                    #    authIdentity 를 생략하면 시스템 할당 관리 ID 가 쓰인다.
                },
            }],
            # 압축 — 벡터 저장 비용을 줄인다. 1만 건 규모에서는 선택이지만
            # 수십만 건으로 늘면 필수가 된다. 재순위(rerank)로 품질 손실을 보상한다.
            "compressions": [{
                "name": "scalar-quantization",
                "kind": "scalarQuantization",
                "scalarQuantizationParameters": {"quantizedDataType": "int8"},
                "rerankWithOriginalVectors": True,
                "defaultOversampling": 4,
            }],
        },

        # ── 시맨틱 구성 (L2 랭커)
        #    ★ 에이전트 검색은 이것을 «내부적으로» 사용한다. 없으면 동작하지 않는다.
        "semantic": {
            "defaultConfiguration": "semantic-config",
            "configurations": [{
                "name": "semantic-config",
                "prioritizedFields": {
                    "titleField": {"fieldName": "title"},
                    "prioritizedContentFields": [{"fieldName": "content"}],
                    "prioritizedKeywordsFields": [
                        {"fieldName": "topic"},
                        {"fieldName": "keywords"},
                    ],
                },
            }],
        },

        # ── 동의어 맵 — BM25 가 «연차»와 «연차유급휴가»를 같게 보도록
        #    ⚠️ 동의어는 «검색 시»에만 적용된다. 색인을 다시 만들 필요는 없다.
        "similarity": {"@odata.type": "#Microsoft.Azure.Search.BM25Similarity",
                       "k1": 1.2, "b": 0.75},

        "corsOptions": {"allowedOrigins": ["*"], "maxAgeInSeconds": 300},

        "_설계메모": {
            "청킹파라미터_출처": "chunk_stats.json — 로컬 실험으로 확정한 값",
            "청크수": chunk_stats.get("청크수"),
            "청크자수_중앙값": chunk_stats.get("청크자수", {}).get("중앙값"),
            "청크자수_최대": chunk_stats.get("청크자수", {}).get("최대"),
            "주의": [
                "content_vector 는 retrievable=false — 응답 크기를 줄이기 위함",
                "security_level 필터는 «선택»이 아니라 «강제»로 적용해야 한다",
                "ko.microsoft 분석기를 지정하지 않으면 한국어 BM25 가 크게 나빠진다",
            ],
        },
    }


# ═══════════════════════════════════════════════════════════ 기술 세트

def build_skillset(chunk_stats):
    """통합 벡터화 기술 세트 — 청킹 + 임베딩을 Azure 가 수행한다.

    로컬 chunker.py 와의 관계
      로컬 청커는 «파라미터를 정하기 위한 실험»이고,
      운영에서는 이 기술 세트가 같은 파라미터로 자른다.
      두 곳의 숫자가 어긋나면 실험 결과가 운영에 적용되지 않는다.

    ⚠️ SplitSkill 은 문서 유형을 구분하지 못한다.
       로컬 청커의 «FAQ 는 자르지 않는다» 같은 분기는 여기서 표현할 수 없다.
       그래서 실제 구축에서는 두 갈래 중 하나를 택한다.
         (가) 유형별로 인덱서를 나눈다 (데이터 원본을 유형별 폴더로 분리)
         (나) 로컬에서 청킹까지 마친 결과를 «푸시»한다 (통합 벡터화를 쓰지 않음)
       이 프로젝트는 (나)를 기본으로 하고, (가)의 구성도 함께 산출한다.
    """
    max_page = chunk_stats.get("파라미터", {}).get("최대자수", 1200)
    overlap = chunk_stats.get("파라미터", {}).get("중첩자수", 120)

    return {
        "name": SKILLSET_NAME,
        "description": "인사·총무 문서 청킹 + 임베딩 (통합 벡터화)",
        "skills": [
            {
                "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
                "name": "split-into-chunks",
                "description": f"최대 {max_page}자, 중첩 {overlap}자로 분할",
                "context": "/document",
                "textSplitMode": "pages",
                "maximumPageLength": max_page,
                "pageOverlapLength": overlap,
                # 한국어 문장 경계를 인식하게 한다
                "defaultLanguageCode": "ko",
                "inputs": [
                    {"name": "text", "source": "/document/content"},
                ],
                "outputs": [
                    {"name": "textItems", "targetName": "pages"},
                ],
            },
            {
                "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
                "name": "embed-chunks",
                "description": f"{EMBEDDING_MODEL} 로 {EMBEDDING_DIM}차원 임베딩",
                "context": "/document/pages/*",
                "resourceUri": "https://{AZURE_OPENAI_RESOURCE}.openai.azure.com",
                "deploymentId": "{EMBEDDING_DEPLOYMENT}",
                "modelName": EMBEDDING_MODEL,
                "dimensions": EMBEDDING_DIM,
                # ⚠️ apiKey 없음 — 검색 서비스 관리 ID 로 인증한다
                "inputs": [
                    {"name": "text", "source": "/document/pages/*"},
                ],
                "outputs": [
                    {"name": "embedding", "targetName": "vector"},
                ],
            },
        ],

        # ★ 인덱스 프로젝션 — 청크를 «자식 인덱스»에 넣는다.
        #   이것이 없으면 청크가 부모 문서의 배열 필드로만 들어가 개별 검색이 안 된다.
        "indexProjections": {
            "selectors": [{
                "targetIndexName": INDEX_NAME,
                "parentKeyFieldName": "parent_id",
                "sourceContext": "/document/pages/*",
                "mappings": [
                    {"name": "content", "source": "/document/pages/*"},
                    {"name": "content_vector", "source": "/document/pages/*/vector"},
                    {"name": "title", "source": "/document/title"},
                    {"name": "category", "source": "/document/category"},
                    {"name": "subcategory", "source": "/document/subcategory"},
                    {"name": "topic", "source": "/document/topic"},
                    {"name": "doc_type", "source": "/document/doc_type"},
                    {"name": "doc_group", "source": "/document/doc_group"},
                    {"name": "status", "source": "/document/status"},
                    {"name": "version", "source": "/document/version"},
                    {"name": "effective_date", "source": "/document/effective_date"},
                    {"name": "expiry_date", "source": "/document/expiry_date"},
                    {"name": "updated_at", "source": "/document/updated_at"},
                    {"name": "security_level", "source": "/document/security_level"},
                    {"name": "audience", "source": "/document/audience"},
                    {"name": "owner_dept", "source": "/document/owner_dept"},
                    {"name": "keywords", "source": "/document/keywords"},
                    {"name": "source_uri", "source": "/document/source_uri"},
                ],
            }],
            "parameters": {
                # 부모 문서는 별도 인덱스에 두지 않는다 (청크만으로 충분)
                "projectionMode": "skipIndexingParentDocuments",
            },
        },

        "_설계메모": {
            "한계": "SplitSkill 은 문서 유형별 분기를 표현할 수 없다",
            "대안": "유형별 인덱서 분리 또는 로컬 청킹 후 푸시",
            "청킹기준": f"최대 {max_page}자 · 중첩 {overlap}자 (로컬 실험으로 확정)",
        },
    }


# ═══════════════════════════════════════════════════════════ 지식 원본 · 지식 베이스

def build_knowledge_source():
    """지식 원본 — 에이전트 검색이 «무엇을» 검색할지 정의한다.

    종류: searchIndex (기존 인덱스를 감싼다)
      이미 우리가 만든 인덱스가 있으므로 이것이 맞다.
      blob/azureSql 종류를 쓰면 Azure 가 인덱서 파이프라인을 «자동 생성»하는데,
      그러면 우리가 정한 청킹·필드 설계를 쓸 수 없다.
    """
    return {
        "name": KNOWLEDGE_SOURCE_NAME,
        "kind": "searchIndex",
        "description": (
            "누리컴퍼니 인사·총무 지식 베이스. "
            "인사(채용·평가·휴가·급여·퇴직)와 총무(비품·출장·경비·계약·복리후생) "
            "규정·지침·FAQ·문의이력·공지를 포함한다."
            # ★ 이 설명문이 중요하다. 검색 추론 노력이 low/medium 일 때
            #   LLM 이 «이 지식 원본을 쓸지» 판단하는 근거가 된다.
        ),
        "searchIndexParameters": {
            "searchIndexName": INDEX_NAME,
            # 답변에 인용할 필드. 너무 많이 넣으면 토큰이 낭비된다.
            "sourceDataSelect": (
                "chunk_id,parent_id,title,content,category,subcategory,"
                "doc_type,status,effective_date,source_uri,security_level"
            ),
        },
    }


def build_knowledge_base(env):
    """지식 베이스 — 에이전트 검색 파이프라인을 오케스트레이션한다.

    동작 순서 (Azure 문서 기준)
      ① 애플리케이션이 검색 작업으로 지식 베이스를 호출
      ② 쿼리 계획 — LLM 이 복잡한 질문을 하위 쿼리로 분해
                     (retrievalReasoningEffort 가 minimal 이면 이 단계를 건너뛴다)
      ③ 쿼리 실행 — 하위 쿼리를 «병렬»로 실행. 각각 시맨틱 재순위를 거친다
      ④ 결과 합성 — 통합 응답 + 참조 + 활동 로그

    비용 구조 — 두 곳에서 과금된다
      · Azure AI Search : 하위 쿼리 실행 + 시맨틱 재순위의 «검색 토큰»
      · Azure OpenAI    : 쿼리 계획 + 답변 합성의 입출력 토큰
    """
    # 환경별 추론 노력 — 비용과 품질의 저울
    effort = {
        "dev": "low",       # 개발: 기본값. 계획은 하되 반복은 안 한다
        "stg": "low",
        "prd": "medium",    # 운영: 반복 단계 추가. 다중 홉 질문에 강해지지만 비용↑
    }[env]

    return {
        "name": KNOWLEDGE_BASE_NAME,
        "description": "인사·총무 문의 응대용 에이전트 검색 파이프라인",
        "knowledgeSources": [{
            "name": KNOWLEDGE_SOURCE_NAME,
            # true 로 두면 추론 노력과 무관하게 «항상» 이 원본을 조회한다.
            # 지식 원본이 하나뿐이므로 true 가 맞다.
            # 여러 개일 때 전부 true 로 두면 팬아웃이 커져 토큰이 낭비된다.
            "alwaysQuery": True,
        }],
        "models": [{
            "kind": "azureOpenAI",
            "azureOpenAIParameters": {
                "resourceUri": "https://{AZURE_OPENAI_RESOURCE}.openai.azure.com",
                "deploymentId": "{CHAT_DEPLOYMENT}",
                "modelName": "{CHAT_MODEL}",
                # ⚠️ apiKey 없음 — 관리 ID 인증
            },
        }],

        # ★ 검색 지침 — LLM 에게 «어떻게 검색할지» 알려 준다. 프롬프트처럼 동작한다.
        "retrievalInstructions": (
            "인사·총무 규정 질의에 답하기 위한 근거를 찾는다.\n"
            "규칙:\n"
            "1. status 가 '폐지'인 문서는 근거로 쓰지 않는다. "
            "   개정 이력을 묻는 질문일 때만 예외로 참고한다.\n"
            "2. 같은 주제에 여러 버전이 있으면 effective_date 가 가장 최근인 것을 우선한다.\n"
            "3. 숫자(일수·금액·기한)를 묻는 질문은 '규정' 또는 '안내서' 유형을 우선한다. "
            "   FAQ 와 문의이력은 요약이라 수치가 다를 수 있다.\n"
            "4. 절차를 묻는 질문은 '지침' 또는 '서식안내' 유형을 우선한다.\n"
            "5. 여러 조건이 걸린 질문(예: 직급 + 상황 + 제도)은 조건별로 하위 쿼리를 나눈다.\n"
        ),

        # 미리 보기 기능 — GA 여부를 배포 전에 다시 확인할 것
        "retrievalReasoningEffort": effort,

        "_설계메모": {
            "환경": env,
            "추론노력": effort,
            "추론노력_의미": {
                "minimal": "LLM 쿼리 계획 생략. 가장 빠르고 싸다. 단순 질의에 적합",
                "low": "LLM 이 하위 쿼리를 만들고 원본을 고른다 (기본값)",
                "medium": "반복 단계 추가. 다중 홉에 강하지만 토큰이 크게 는다",
            },
            "API버전_주의": (
                f"retrievalReasoningEffort 는 {API_PREVIEW} 에서 미리 보기다. "
                f"운영 도입 전에 {API_GA} 로 GA 되었는지 확인할 것"
            ),
            "비용통제": [
                "지식 원본 수를 줄이면 팬아웃이 줄어 토큰이 절약된다",
                "활동 로그로 실제 실행된 하위 쿼리를 확인해 낭비를 찾는다",
                "단순 질의는 minimal, 복잡 질의만 medium 으로 라우팅하는 것이 이상적",
            ],
        },
    }


# ═══════════════════════════════════════════════════════════ 데이터 원본 · 인덱서

def build_datasource():
    """Blob 데이터 원본.

    ⚠️ 연결 문자열을 쓰지 않는다. 관리 ID 로 인증한다.
       connectionString 에 «ResourceId=…» 형식을 쓰면 키 없이 연결된다.
    """
    return {
        "name": DATASOURCE_NAME,
        "type": "azureblob",
        "credentials": {
            # 키 없는 연결. 검색 서비스의 관리 ID 에
            # Storage Blob 데이터 판독기 역할이 부여되어 있어야 한다.
            "connectionString": (
                "ResourceId=/subscriptions/{SUBSCRIPTION_ID}"
                "/resourceGroups/{RESOURCE_GROUP}"
                "/providers/Microsoft.Storage/storageAccounts/{STORAGE_ACCOUNT};"
            ),
        },
        "container": {"name": "hr-ga-corpus"},
        "dataChangeDetectionPolicy": {
            "@odata.type": "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy",
            "highWaterMarkColumnName": "metadata_storage_last_modified",
        },
        "dataDeletionDetectionPolicy": {
            "@odata.type": "#Microsoft.Azure.Search.SoftDeleteColumnDeletionDetectionPolicy",
            "softDeleteColumnName": "IsDeleted",
            "softDeleteMarkerValue": "true",
        },
    }


def build_indexer():
    return {
        "name": INDEXER_NAME,
        "dataSourceName": DATASOURCE_NAME,
        "targetIndexName": INDEX_NAME,
        "skillsetName": SKILLSET_NAME,
        "schedule": {
            # 5분 주기 — Azure OpenAI 속도 제한에 걸린 호출을 재시도로 흡수하기 위함.
            # 너무 짧으면 인덱서가 겹치고, 너무 길면 반영이 늦어진다.
            "interval": "PT5M",
        },
        "parameters": {
            "batchSize": 50,
            "maxFailedItems": 10,
            "maxFailedItemsPerBatch": 5,
            "configuration": {
                "dataToExtract": "contentAndMetadata",
                "parsingMode": "jsonLines",
            },
        },
        "fieldMappings": [
            {"sourceFieldName": "doc_id", "targetFieldName": "parent_id"},
        ],
    }


# ═══════════════════════════════════════════════════════════ 실행

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Azure AI Search 구성 파일 생성")
    ap.add_argument("--env", choices=["dev", "stg", "prd"], default="dev")
    ap.add_argument("--out", default=here)
    args = ap.parse_args()

    stats_path = os.path.join(here, "..", "data", "chunk_stats.json")
    chunk_stats = {}
    if os.path.exists(stats_path):
        chunk_stats = json.load(io.open(stats_path, encoding="utf-8"))

    artifacts = {
        "index.json": build_index(chunk_stats),
        "skillset.json": build_skillset(chunk_stats),
        "datasource.json": build_datasource(),
        "indexer.json": build_indexer(),
        "knowledge_source.json": build_knowledge_source(),
        f"knowledge_base.{args.env}.json": build_knowledge_base(args.env),
    }

    print("=" * 68)
    print(f" Azure AI Search 구성 생성 — {args.env}")
    print("=" * 68)
    print(f" API  GA {API_GA} · 미리보기 {API_PREVIEW}")
    print(f" 청크 {chunk_stats.get('청크수', '?')}건 기준")
    print()

    out_dir = os.path.abspath(args.out)
    for name, obj in artifacts.items():
        path = os.path.join(out_dir, name)
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
        print(f"  → {name}")

    # 환경 변수 템플릿 — ⚠️ 실제 값은 여기에 쓰지 않는다
    env_path = os.path.join(out_dir, ".env.example")
    with io.open(env_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(
            "# Azure 리소스 좌표. ⚠️ 비밀은 여기에 두지 않는다.\n"
            "# 인증은 관리 ID(운영) 또는 az login(개발)으로 한다.\n"
            "\n"
            "AZURE_SEARCH_ENDPOINT=https://<검색서비스>.search.windows.net\n"
            "AZURE_SEARCH_INDEX=" + INDEX_NAME + "\n"
            "AZURE_SEARCH_KNOWLEDGE_BASE=" + KNOWLEDGE_BASE_NAME + "\n"
            "\n"
            "AZURE_OPENAI_ENDPOINT=https://<리소스>.openai.azure.com\n"
            "AZURE_OPENAI_EMBEDDING_DEPLOYMENT=text-embedding-3-large\n"
            "AZURE_OPENAI_CHAT_DEPLOYMENT=<채팅 배포명>\n"
            "\n"
            "SUBSCRIPTION_ID=<구독 ID>\n"
            "RESOURCE_GROUP=<리소스 그룹>\n"
            "STORAGE_ACCOUNT=<스토리지 계정>\n"
            "\n"
            "# ⛔ 아래는 «절대» 쓰지 않는다\n"
            "# AZURE_SEARCH_API_KEY=...\n"
            "# AZURE_OPENAI_API_KEY=...\n"
        )
    print(f"  → .env.example")

    print()
    print("-" * 68)
    print(" ⚠️ 이 스크립트는 파일만 만들었습니다. Azure 에 배포하지 않았습니다.")
    print("    배포: python deploy_index.py --env " + args.env)
    print()
    print(" 배포 전 치환이 필요한 자리표시자")
    print("    {AZURE_OPENAI_RESOURCE} {EMBEDDING_DEPLOYMENT}")
    print("    {CHAT_DEPLOYMENT} {CHAT_MODEL}")
    print("    {SUBSCRIPTION_ID} {RESOURCE_GROUP} {STORAGE_ACCOUNT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
