# 메시징 — Service Bus(명령 큐) + Event Hubs(이벤트 스트림).
#
# 왜 둘 다 필요한가 (설계/01 §5.1)
#   Service Bus 큐 — «명령». 정확히 하나가 처리. 유실 불가. DLQ 필수.
#   Event Hubs     — «이벤트». 여럿이 각자 처리. 높은 처리량. 재생 가능.
# 하나로 합치면 «명령을 여럿이 중복 처리»하거나 «이벤트 처리량이 부족»해진다.

# ─────────────────────────────────────────── Service Bus

resource "azurerm_servicebus_namespace" "main" {
  name                = var.service_bus_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.service_bus_sku

  # ★ Premium 에서만 프라이빗 엔드포인트를 쓸 수 있다.
  public_network_access_enabled = var.public_network_access
  minimum_tls_version           = "1.2"

  # Premium 이 아니면 capacity 를 지정할 수 없다.
  capacity = var.service_bus_sku == "Premium" ? 1 : 0

  # ⛔ 로컬 인증(SAS 키) 비활성 — 관리 ID 만 허용한다 (SEC-01).
  local_auth_enabled = var.service_bus_local_auth_enabled

  tags = var.tags
}

resource "azurerm_servicebus_queue" "delivery_requests" {
  name         = "delivery-requests"
  namespace_id = azurerm_servicebus_namespace.main.id

  # 피어‑락 — 처리 완료를 확인한 뒤에만 메시지를 지운다 (REL-05 유실 0건).
  lock_duration = "PT5M" # 처리 예산 30초에 충분한 여유

  # 5회 실패하면 배달 못한 편지 큐로 보낸다.
  # 무한 재시도는 «독 메시지»가 큐를 영원히 막게 만든다.
  max_delivery_count                   = 5
  dead_lettering_on_message_expiration = true

  # 중복 감지 — MessageId 를 deliveryId 로 두면 같은 배달의 중복 요청이 걸러진다.
  # ⚠️ Basic SKU 는 지원하지 않는다.
  requires_duplicate_detection            = var.service_bus_sku != "Basic"
  duplicate_detection_history_time_window = "PT10M"

  # 세션 미사용 — 배달 간에는 순서 의존이 없다.
  requires_session = false

  default_message_ttl   = "P1D"
  max_size_in_megabytes = 1024
}

# ─────────────────────────────────────────── Event Hubs

resource "azurerm_eventhub_namespace" "main" {
  name                = var.event_hubs_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.event_hubs_sku
  capacity            = var.event_hubs_capacity

  public_network_access_enabled = var.public_network_access
  minimum_tls_version           = "1.2"
  local_authentication_enabled  = var.eventhub_local_auth_enabled

  # 자동 팽창 — 갑작스러운 텔레메트리 폭증에 스스로 대응한다 (Standard 이상).
  auto_inflate_enabled     = var.event_hubs_sku != "Basic"
  maximum_throughput_units = var.event_hubs_sku != "Basic" ? var.event_hubs_max_capacity : null

  tags = var.tags
}

resource "azurerm_eventhub" "delivery_tracking" {
  name         = "delivery-tracking"
  namespace_id = azurerm_eventhub_namespace.main.id

  # 파티션 키 = deliveryId → 같은 배달의 이벤트는 같은 파티션 → 순서 보장.
  partition_count   = var.delivery_tracking_partitions
  message_retention = var.retention_days
}

resource "azurerm_eventhub" "drone_status" {
  name         = "drone-status"
  namespace_id = azurerm_eventhub_namespace.main.id

  # 텔레메트리는 처리량이 훨씬 높다 → 파티션을 더 많이 (NFR-04: 10,000 msg/s).
  partition_count   = var.drone_status_partitions
  message_retention = var.retention_days
}

# 소비자 그룹 — 각 소비자가 «자기 진도»를 따로 갖는다.
# 하나를 공유하면 한 소비자의 체크포인트가 다른 소비자에게 영향을 준다.
resource "azurerm_eventhub_consumer_group" "history" {
  name                = "history"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.delivery_tracking.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_eventhub_consumer_group" "billing" {
  name                = "billing"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.delivery_tracking.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_eventhub_consumer_group" "eta" {
  name                = "eta"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.drone_status.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_eventhub_consumer_group" "analytics" {
  name                = "analytics"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.drone_status.name
  resource_group_name = var.resource_group_name
}
