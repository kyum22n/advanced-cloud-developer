# API 게이트웨이 — Application Gateway + WAF (설계/05).
#
# 역할 (셋 다 «각 서비스가 중복 구현하지 않게» 하는 것이 목적)
#   ① 라우팅    경로·메서드에 따라 올바른 백엔드로
#   ② 오프로딩  TLS 종료 · WAF · 속도 제한 · CORS
#   ③ 은닉      내부 서비스 구조를 클라이언트에게 감춘다
#
# ⚠️ 집계는 하지 않는다 — 게이트웨이가 도메인을 알게 되면 «또 하나의 서비스»가 된다.

resource "azurerm_public_ip" "appgw" {
  count = var.enabled ? 1 : 0

  name                = "pip-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zone_redundant ? ["1", "2", "3"] : null
  tags                = var.tags
}

resource "azurerm_web_application_firewall_policy" "main" {
  count = var.enabled ? 1 : 0

  name                = "waf-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  policy_settings {
    enabled = true
    # ★ stg 는 Detection(감지), prd 는 Prevention(차단).
    #   바로 차단 모드로 켜면 정상 요청이 막혀 장애로 인식된다.
    #   stg 에서 최소 2주 로그를 본 뒤 prd 를 차단으로 전환한다 (설계/05 §4.2).
    mode                        = var.waf_mode
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  # 속도 제한 — 한 클라이언트가 자원을 독점하지 못하게 한다.
  # 이것은 «공정성»이고, 각 서비스의 Bulkhead 는 «시스템 보호»다. 둘 다 필요하다.
  dynamic "custom_rules" {
    for_each = var.enable_rate_limit ? [1] : []
    content {
      name      = "RateLimitPerIp"
      priority  = 100
      rule_type = "RateLimitRule"
      action    = "Block"

      rate_limit_duration  = "OneMin"
      rate_limit_threshold = var.rate_limit_per_minute
      group_rate_limit_by  = "ClientAddr"

      match_conditions {
        match_variables {
          variable_name = "RemoteAddr"
        }
        operator           = "IPMatch"
        negation_condition = false
        match_values       = ["0.0.0.0/0"]
      }
    }
  }

  tags = var.tags
}

resource "azurerm_application_gateway" "main" {
  count = var.enabled ? 1 : 0

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  zones               = var.zone_redundant ? ["1", "2", "3"] : null

  firewall_policy_id = azurerm_web_application_firewall_policy.main[0].id

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = var.subnet_id
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw[0].id
  }

  # ── 백엔드 풀 — 앱마다 하나
  dynamic "backend_address_pool" {
    for_each = var.backends
    content {
      name  = "pool-${backend_address_pool.key}"
      fqdns = [backend_address_pool.value.fqdn]
    }
  }

  # ── 상태 프로브 — 준비된 인스턴스에만 트래픽을 보낸다
  dynamic "probe" {
    for_each = var.backends
    content {
      name                                      = "probe-${probe.key}"
      protocol                                  = "Https"
      path                                      = "/actuator/health/readiness"
      interval                                  = 15
      timeout                                   = 10
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true

      match {
        status_code = ["200-399"]
      }
    }
  }

  dynamic "backend_http_settings" {
    for_each = var.backends
    content {
      name     = "settings-${backend_http_settings.key}"
      port     = 443
      protocol = "Https"
      # ★ 백엔드로 다시 암호화한다 — 종단 간 TLS (SEC-07).
      #   게이트웨이에서 복호화해 WAF 검사를 한 뒤 재암호화한다.
      cookie_based_affinity               = "Disabled"
      request_timeout                     = 30
      probe_name                          = "probe-${backend_http_settings.key}"
      pick_host_name_from_backend_address = true
    }
  }

  http_listener {
    name                           = "listener-https"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "port-443"
    protocol                       = "Https"
    ssl_certificate_name           = "cert-main"
  }

  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  # HTTP 는 전부 HTTPS 로 돌린다 — 평문 접근을 허용하지 않는다.
  redirect_configuration {
    name                 = "redirect-to-https"
    redirect_type        = "Permanent"
    target_listener_name = "listener-https"
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = "rule-http-redirect"
    priority                    = 10
    rule_type                   = "Basic"
    http_listener_name          = "listener-http"
    redirect_configuration_name = "redirect-to-https"
  }

  # ── 경로 기반 라우팅
  #
  # 같은 /api/v1/deliveries 경로가 «쓰기는 Ingestion, 읽기는 Delivery» 로 갈린다.
  # CQRS 가 게이트웨이 라우팅으로 드러나는 지점이다.
  # ⚠️ Application Gateway 는 메서드 기반 라우팅을 직접 지원하지 않으므로,
  #    실제로는 재작성 규칙 또는 경로 분리(/api/v1/deliveries/{id}/status)로 처리한다.
  url_path_map {
    name                               = "path-map"
    default_backend_address_pool_name  = "pool-${var.default_backend}"
    default_backend_http_settings_name = "settings-${var.default_backend}"

    dynamic "path_rule" {
      for_each = var.path_rules
      content {
        name                       = path_rule.key
        paths                      = path_rule.value.paths
        backend_address_pool_name  = "pool-${path_rule.value.backend}"
        backend_http_settings_name = "settings-${path_rule.value.backend}"
      }
    }
  }

  request_routing_rule {
    name               = "rule-https-path"
    priority           = 20
    rule_type          = "PathBasedRouting"
    http_listener_name = "listener-https"
    url_path_map_name  = "path-map"
  }

  # ── TLS 인증서
  #
  # ★ Key Vault 참조 — 인증서 파일을 Terraform 상태나 Git 에 두지 않는다.
  #   Key Vault 에서 갱신하면 게이트웨이가 자동으로 새 인증서를 쓴다.
  ssl_certificate {
    name                = "cert-main"
    key_vault_secret_id = var.tls_certificate_key_vault_id
  }

  # 게이트웨이가 Key Vault 를 읽으려면 자기 ID 가 필요하다.
  identity {
    type         = "UserAssigned"
    identity_ids = [var.gateway_identity_id]
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101" # TLS 1.2 이상
  }

  tags = var.tags

  depends_on = [azurerm_web_application_firewall_policy.main]
}
