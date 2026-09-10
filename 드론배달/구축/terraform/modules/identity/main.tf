# 아이덴티티 — 앱마다 사용자 할당 관리 ID 하나씩.
#
# 원칙 (설계/09_보안_아이덴티티_설계서.md)
#   ✅ 하나의 앱 = 하나의 ID = 필요한 리소스에만 최소 권한
#   ⛔ 구독 범위 역할 금지 (A-01)
#   ⛔ Contributor · Owner 금지 (A-02)
#   ⛔ 여러 앱이 ID 공유 금지 (A-03)
#   ⛔ 시스템 할당 ID 금지 (A-04) — 리소스 재생성 시 ID 가 바뀌어 역할이 끊긴다
#
# 왜 사용자 할당인가 — 시스템 할당 ID 는 리소스와 수명을 함께한다.
# 앱을 다시 만들면 ID 가 새로 생기고, 부여해 둔 역할이 전부 무효가 된다.
# 사용자 할당은 독립적으로 존재하므로 그런 일이 없다.

resource "azurerm_user_assigned_identity" "apps" {
  for_each = var.identity_names

  name                = each.value
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ─────────────────────────────────────────── 역할 할당
#
# 각 역할은 «리소스 범위»로만 부여한다. 리소스 그룹이나 구독 범위로 주면
# 앱 하나가 침해됐을 때 피해가 그 범위 전체로 번진다.

locals {
  # 앱 → 필요한 역할 목록.
  # 이 표가 곧 «최소 권한»의 정의다. 여기 없는 권한은 없다.
  role_assignments = {
    ingestion_servicebus = {
      identity = "ingestion"
      scope    = var.service_bus_queue_id
      role     = "Azure Service Bus Data Sender"
    }
    workflow_servicebus = {
      identity = "workflow"
      scope    = var.service_bus_queue_id
      role     = "Azure Service Bus Data Receiver"
    }
    delivery_eventhub_send = {
      identity = "delivery"
      scope    = var.eventhub_delivery_tracking_id
      role     = "Azure Event Hubs Data Sender"
    }
    delivery_eventhub_receive = {
      identity = "delivery"
      scope    = var.eventhub_drone_status_id
      role     = "Azure Event Hubs Data Receiver"
    }
    dronesched_eventhub_send = {
      identity = "dronesched"
      scope    = var.eventhub_drone_status_id
      role     = "Azure Event Hubs Data Sender"
    }
    history_eventhub_receive = {
      identity = "history"
      scope    = var.eventhub_delivery_tracking_id
      role     = "Azure Event Hubs Data Receiver"
    }
    history_storage = {
      identity = "history"
      scope    = var.storage_container_id
      role     = "Storage Blob Data Contributor"
    }
  }
}

resource "azurerm_role_assignment" "app_roles" {
  for_each = {
    for k, v in local.role_assignments : k => v
    if v.scope != null
  }

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.apps[each.value.identity].principal_id
}

# ─────────────────────────────────────────── Cosmos DB 데이터 평면 RBAC
#
# Cosmos DB 는 Azure RBAC 와 «별도의» 데이터 평면 역할 체계를 쓴다.
# 관리 평면 역할(Contributor)을 줘도 데이터를 읽을 수 없고, 그 반대도 마찬가지다.
# 이 분리가 «키 없이 데이터에만 접근»을 가능하게 한다.

resource "azurerm_cosmosdb_sql_role_assignment" "data_contributor" {
  for_each = var.cosmos_account_name == null ? {} : {
    dronesched = azurerm_user_assigned_identity.apps["dronesched"].principal_id
    history    = azurerm_user_assigned_identity.apps["history"].principal_id
  }

  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_account_name
  # 00000000-0000-0000-0000-000000000002 = 기본 제공 데이터 기여자
  role_definition_id = "${var.cosmos_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id       = each.value
  scope              = var.cosmos_account_id
}

# ─────────────────────────────────────────── ACR 이미지 풀

resource "azurerm_role_assignment" "acr_pull" {
  for_each = var.container_registry_id == null ? {} : var.identity_names

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.apps[each.key].principal_id
}
