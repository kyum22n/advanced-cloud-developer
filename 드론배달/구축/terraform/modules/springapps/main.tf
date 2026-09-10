# Azure Spring Apps — 6개 마이크로서비스의 호스팅 (ADR-004).
#
# 왜 AKS 가 아닌가 (설계/02_컴퓨팅_플랫폼_선정서.md §4.2)
#   · 애플리케이션이 Kubernetes API 를 쓰지 않는다
#   · 노드/OS 수준 제어가 필요 없다
#   · 서비스 검색·구성·분산 추적을 플랫폼이 제공한다 → 운영 부담이 줄어든다
#   · CON-02 가 Java/Spring 으로 고정 → «다중 언어» 이점이 이 프로젝트에서는 가치가 없다
#
# 되돌릴 조건 — Java 아닌 서비스 필요 · Pod 수준 네트워크 정책 필수 · 서비스 20개 초과.
# 그래서 모든 서비스를 컨테이너 이미지로도 빌드해 이식성을 남겨 둔다.

resource "azurerm_spring_cloud_service" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = var.sku

  # VNet 주입 — stg·prd 에서 프라이빗 엔드포인트에 접근하려면 필수.
  dynamic "network" {
    for_each = var.vnet_injection ? [1] : []
    content {
      app_subnet_id             = var.app_subnet_id
      service_runtime_subnet_id = var.runtime_subnet_id
      cidr_ranges               = var.service_cidr_ranges
    }
  }

  # ★ 구성 서버 — 환경별 설정을 이미지가 아니라 Git 에서 읽는다.
  #   외부 구성 저장소 패턴. 이미지를 다시 굽지 않고 설정을 바꿀 수 있다.
  dynamic "config_server_git_setting" {
    for_each = var.config_repo_uri == null ? [] : [1]
    content {
      uri          = var.config_repo_uri
      label        = var.config_repo_label
      search_paths = var.config_repo_search_paths
    }
  }

  trace {
    connection_string = var.app_insights_connection_string
    sample_rate       = var.trace_sample_rate
  }

  tags = var.tags
}

# ─────────────────────────────────────────── 애플리케이션

resource "azurerm_spring_cloud_app" "apps" {
  for_each = var.apps

  name                = each.key
  resource_group_name = var.resource_group_name
  service_name        = azurerm_spring_cloud_service.main.name

  # 공개 엔드포인트는 꼭 필요한 앱에만 (설계/02 §5.2 — 6개 중 3개).
  # 나머지는 클러스터 내부에서만 접근 가능하다.
  is_public = each.value.public

  https_only = true

  # ★ 앱별 사용자 할당 관리 ID — 하나의 앱 = 하나의 ID (설계/09 §4).
  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_ids[each.value.identity_key]]
  }
}

resource "azurerm_spring_cloud_java_deployment" "apps" {
  for_each = var.apps

  name                = "default"
  spring_cloud_app_id = azurerm_spring_cloud_app.apps[each.key].id

  instance_count  = each.value.instances_min
  runtime_version = "Java_17"

  quota {
    cpu    = each.value.cpu
    memory = each.value.memory
  }

  environment_variables = merge(
    {
      ENVIRONMENT      = var.env
      AZURE_MI_ENABLED = "true"
      # ★ 관리 ID 가 여러 개 붙을 수 있으므로 어느 것을 쓸지 명시해야 한다.
      AZURE_CLIENT_ID = var.client_ids[each.value.identity_key]
      TRACE_SAMPLING  = tostring(var.trace_sample_rate)
      # prd 에서는 Swagger UI 와 상세 상태를 노출하지 않는다 (SEC-15 · SEC-16).
      SWAGGER_ENABLED = var.env == "prd" ? "false" : "true"
      HEALTH_DETAILS  = var.env == "prd" ? "never" : "when_authorized"
      LOG_LEVEL       = var.env == "dev" ? "DEBUG" : "INFO"
    },
    var.common_environment_variables,
    lookup(each.value, "environment_variables", {})
  )

  lifecycle {
    # 배포 파이프라인이 JAR/이미지를 바꾸므로 Terraform 이 되돌리지 않게 한다.
    # 인프라와 워크로드를 분리해 배포하는 것이 원칙이다 (OPS-03).
    ignore_changes = [instance_count]
  }
}

resource "azurerm_spring_cloud_active_deployment" "apps" {
  for_each = var.apps

  spring_cloud_app_id = azurerm_spring_cloud_app.apps[each.key].id
  deployment_name     = azurerm_spring_cloud_java_deployment.apps[each.key].name
}
