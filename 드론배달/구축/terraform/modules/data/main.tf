# 데이터 — 폴리글랏 저장소 (설계/06_데이터_설계서.md).
#
#   Redis        배달 상태 · ETA        읽기 p95 150ms · 짧은 수명 · TTL 자동 만료
#   Cosmos NoSQL 드론 · 이력(핫)         ETag 조건부 쓰기로 INV-03 보장
#   Cosmos Mongo 패키지                  문서형 · 높은 쓰기 처리량
#   Data Lake    이력(콜드)              날짜 파티션 · 저비용 · 분석
#
# 하나로 합치면 어느 것도 최적이 아니다. 나눈 대가로 분산 트랜잭션을 포기하고
# Saga 를 쓴다 — 그것이 ADR-007 의 거래 조건이다.

# ─────────────────────────────────────────── Redis

resource "azurerm_redis_cache" "main" {
  name                = var.redis_name
  resource_group_name = var.resource_group_name
  location            = var.location

  capacity = var.redis_capacity
  family   = var.redis_family
  sku_name = var.redis_sku

  non_ssl_port_enabled = false # ⛔ 평문 포트 차단
  minimum_tls_version  = "1.2"

  public_network_access_enabled = var.public_network_access

  # 영역 중복 — Premium 에서만 가능. prd 의 가용성 99.9% 근거.
  zones = var.redis_sku == "Premium" ? var.availability_zones : null

  redis_configuration {
    # AOF 지속성 — Premium 에서만. 다만 «원본은 이벤트 스트림»이므로
    # Redis 유실이 곧 데이터 유실은 아니다 (설계/06 §9).
    aof_backup_enabled = var.redis_sku == "Premium"

    # 메모리가 차면 «가장 오래 안 쓴 것»부터 버린다.
    # 배달 상태는 TTL 로도 관리되므로 이 정책이 안전하다.
    maxmemory_policy = "allkeys-lru"
  }

  tags = var.tags
}

# ─────────────────────────────────────────── Cosmos DB (NoSQL)

resource "azurerm_cosmosdb_account" "nosql" {
  name                = var.cosmos_name
  resource_group_name = var.resource_group_name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # ⛔ 계정 키 비활성 — 데이터 평면 RBAC 만 허용 (SEC-01 · A-08).
  local_authentication_disabled = var.cosmos_local_auth_disabled

  public_network_access_enabled = var.public_network_access
  minimal_tls_version           = "Tls12"

  automatic_failover_enabled = var.enable_zone_redundancy

  consistency_policy {
    # 기본은 Session. 강력한 일관성이 필요한 컨테이너(drones)는
    # 애플리케이션에서 요청 단위로 올린다 — 전역 Strong 은 비싸고 느리다.
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = var.enable_zone_redundancy
  }

  capabilities {
    name = var.cosmos_serverless ? "EnableServerless" : "EnableNoSQLVectorSearch"
  }

  backup {
    type = "Continuous"
    tier = "Continuous7Days"
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "dronedelivery"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.nosql.name

  # 서버리스에서는 처리량을 지정할 수 없다.
  dynamic "autoscale_settings" {
    for_each = var.cosmos_serverless ? [] : [1]
    content {
      max_throughput = var.cosmos_max_throughput
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "drones" {
  name                = "drones"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.nosql.name
  database_name       = azurerm_cosmosdb_sql_database.main.name

  # 파티션 키 = droneId → 모든 접근이 단일 파티션 → RU 최소.
  partition_key_paths   = ["/droneId"]
  partition_key_version = 2
}

resource "azurerm_cosmosdb_sql_container" "history" {
  name                = "delivery-history"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.nosql.name
  database_name       = azurerm_cosmosdb_sql_database.main.name

  partition_key_paths   = ["/deliveryId"]
  partition_key_version = 2

  # ★ 30일 TTL — 이후에는 Data Lake(콜드)에서만 조회한다 (COST-04 자동 계층화).
  default_ttl = 2592000
}

# ─────────────────────────────────────────── Cosmos DB (MongoDB API)

resource "azurerm_cosmosdb_account" "mongo" {
  name                = var.cosmos_mongo_name
  resource_group_name = var.resource_group_name
  location            = var.location
  offer_type          = "Standard"
  kind                = "MongoDB"

  public_network_access_enabled = var.public_network_access
  minimal_tls_version           = "Tls12"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = var.enable_zone_redundancy
  }

  capabilities { name = "EnableMongo" }
  capabilities { name = "DisableRateLimitingResponses" }

  dynamic "capabilities" {
    for_each = var.cosmos_serverless ? [1] : []
    content { name = "EnableServerless" }
  }

  mongo_server_version = "4.2"

  backup {
    type = "Continuous"
    tier = "Continuous7Days"
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_mongo_database" "packages" {
  name                = "dronedelivery"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.mongo.name

  dynamic "autoscale_settings" {
    for_each = var.cosmos_serverless ? [] : [1]
    content {
      max_throughput = var.cosmos_max_throughput
    }
  }
}

# ─────────────────────────────────────────── Data Lake Storage

resource "azurerm_storage_account" "lake" {
  name                     = var.storage_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication
  account_kind             = "StorageV2"

  is_hns_enabled = true # 계층적 네임스페이스 = Data Lake Gen2

  # ⛔ 공유 키 접근 차단 — 관리 ID 만 허용 (SEC-01 · A-07).
  shared_access_key_enabled = var.storage_shared_key_enabled

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = var.public_network_access
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "history" {
  name                  = "history"
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

# 정적 웹사이트용 컨테이너 (Vue SPA)
resource "azurerm_storage_container" "web" {
  name                  = "$web"
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}
