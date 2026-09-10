# 플랫폼 서비스 — Container Registry + Key Vault.

resource "azurerm_container_registry" "main" {
  name                = var.container_registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.acr_sku

  # ⛔ 관리자 계정 비활성 — 사용자명/비밀번호 로그인을 막고 관리 ID 만 허용한다.
  admin_enabled = false

  public_network_access_enabled = var.public_network_access

  # Premium 에서만 가능한 기능들
  dynamic "retention_policy_in_days" {
    for_each = var.acr_sku == "Premium" ? [1] : []
    content {
      days    = 30
      enabled = true
    }
  }

  tags = var.tags
}

# ─────────────────────────────────────────── Key Vault
#
# ⚠️ Key Vault 는 «2순위» 수단이다 (설계/09 §1).
#    1순위는 관리 ID 로 리소스에 직접 접근하는 것이고,
#    Key Vault 는 Entra 인증을 지원하지 않는 경로에만 쓴다.
#    (Cosmos Mongo 연결 문자열 · 타사 API 키 · TLS 인증서)

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # ★ RBAC 권한 모델 — 액세스 정책보다 감사·관리가 쉽다.
  enable_rbac_authorization = true

  # 실수로 지워도 복구할 수 있게 한다. 비밀을 영구 삭제하면 되돌릴 수 없다.
  soft_delete_retention_days = 90
  purge_protection_enabled   = var.purge_protection_enabled

  public_network_access_enabled = var.public_network_access

  network_acls {
    bypass         = "AzureServices"
    default_action = var.public_network_access ? "Allow" : "Deny"
  }

  tags = var.tags
}

# 앱이 Key Vault 비밀을 읽을 수 있게 한다 — «비밀 사용자» 역할만.
# 「비밀 관리자」를 주면 앱이 비밀을 «쓸» 수 있게 되어 최소 권한이 아니다.
resource "azurerm_role_assignment" "kv_secret_user" {
  for_each = var.secret_reader_principal_ids

  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}
