# DEV 환경.
#
# ⚠️ 이 파일은 «모듈을 조립만» 한다. 리소스를 직접 선언하지 않는다.
#    그래야 dev·stg·prd 가 «구조적으로 동일함»이 코드로 증명된다.
#    환경 차이는 terraform.tfvars 의 «값»에만 있다.

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    key_vault {
      # ⚠️ 실수로 비밀을 영구 삭제하지 못하게 한다.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      # 리소스가 남아 있는 리소스 그룹을 통째로 지우지 못하게 한다.
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "current" {}

# ─────────────────────────────────────────── 이름 · 태그

module "naming" {
  source = "../../modules/naming"

  system       = var.system
  env          = "dev"
  region_short = var.region_short
  owner        = var.owner
  cost_center  = var.cost_center
  deployed_at  = var.deployed_at
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group
  location = var.location
  tags     = module.naming.tags
}

# ─────────────────────────────────────────── 관측성 (가장 먼저)
#
# 다른 리소스의 진단 설정이 이것을 참조하므로 먼저 만든다.
# 나중에 붙이면 «그동안의 로그가 없는» 구간이 생긴다.

module "observability" {
  source = "../../modules/observability"

  log_analytics_name    = module.naming.log_analytics
  app_insights_name     = module.naming.app_insights
  name_suffix           = module.naming.prefix
  resource_group_name   = azurerm_resource_group.main.name
  resource_group_id     = azurerm_resource_group.main.id
  location              = var.location
  retention_days        = var.log_retention_days
  sampling_percentage   = var.trace_sampling_percentage
  monthly_budget_amount = var.monthly_budget_amount
  budget_start_date     = var.budget_start_date
  budget_contact_emails = var.budget_contact_emails
  tags                  = module.naming.tags
}

# ─────────────────────────────────────────── 네트워크

module "network" {
  source = "../../modules/network"

  enabled             = var.vnet_enabled
  vnet_name           = module.naming.vnet
  name_suffix         = module.naming.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  address_space       = var.vnet_address_space
  hub_vnet_id         = var.hub_vnet_id
  tags                = module.naming.tags
}

# ─────────────────────────────────────────── 플랫폼 (ACR · Key Vault)

module "platform" {
  source = "../../modules/platform"

  container_registry_name  = module.naming.container_registry
  key_vault_name           = module.naming.key_vault
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  tenant_id                = data.azurerm_client_config.current.tenant_id
  acr_sku                  = var.acr_sku
  public_network_access    = var.public_network_access
  purge_protection_enabled = var.key_vault_purge_protection

  secret_reader_principal_ids = module.identity.principal_ids

  tags = module.naming.tags
}

# ─────────────────────────────────────────── 메시징

module "messaging" {
  source = "../../modules/messaging"

  service_bus_name    = module.naming.service_bus
  event_hubs_name     = module.naming.event_hubs
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  service_bus_sku              = var.service_bus_sku
  event_hubs_sku               = var.event_hubs_sku
  event_hubs_capacity          = var.event_hubs_capacity
  event_hubs_max_capacity      = var.event_hubs_max_capacity
  delivery_tracking_partitions = var.delivery_tracking_partitions
  drone_status_partitions      = var.drone_status_partitions
  retention_days               = var.eventhub_retention_days
  public_network_access        = var.public_network_access

  tags = module.naming.tags
}

# ─────────────────────────────────────────── 데이터

module "data" {
  source = "../../modules/data"

  redis_name          = module.naming.redis
  cosmos_name         = module.naming.cosmos
  cosmos_mongo_name   = module.naming.cosmos_mongo
  storage_name        = module.naming.storage
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  redis_sku              = var.redis_sku
  redis_family           = var.redis_family
  redis_capacity         = var.redis_capacity
  cosmos_serverless      = var.cosmos_serverless
  cosmos_max_throughput  = var.cosmos_max_throughput
  storage_replication    = var.storage_replication
  public_network_access  = var.public_network_access
  enable_zone_redundancy = var.enable_zone_redundancy

  tags = module.naming.tags
}

# ─────────────────────────────────────────── 아이덴티티
#
# 데이터·메시징 «뒤에» 온다 — 역할을 부여하려면 대상 리소스가 있어야 한다.

module "identity" {
  source = "../../modules/identity"

  identity_names      = module.naming.identity_names
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  service_bus_queue_id          = module.messaging.delivery_requests_queue_id
  eventhub_delivery_tracking_id = module.messaging.delivery_tracking_id
  eventhub_drone_status_id      = module.messaging.drone_status_id
  storage_container_id          = module.data.history_container_id
  cosmos_account_id             = module.data.cosmos_account_id
  cosmos_account_name           = module.data.cosmos_account_name
  container_registry_id         = module.platform.container_registry_id

  tags = module.naming.tags
}

# ─────────────────────────────────────────── 애플리케이션 호스팅

module "spring_apps" {
  source = "../../modules/springapps"

  name                = module.naming.spring_apps
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  env                 = "dev"
  sku                 = var.spring_apps_sku

  vnet_injection    = var.vnet_enabled
  app_subnet_id     = module.network.subnet_apps_id
  runtime_subnet_id = module.network.subnet_runtime_id

  identity_ids = module.identity.identity_ids
  client_ids   = module.identity.client_ids

  app_insights_connection_string = module.observability.app_insights_connection_string
  trace_sample_rate              = var.trace_sampling_percentage

  # ⛔ 여기에 비밀을 넣지 않는다. 엔드포인트 «주소»만 넣는다.
  #    자격 증명은 런타임에 관리 ID 로 얻는다.
  common_environment_variables = {
    SERVICEBUS_NAMESPACE = module.messaging.service_bus_namespace
    EVENTHUB_NAMESPACE   = module.messaging.event_hubs_namespace
    COSMOS_ENDPOINT      = module.data.cosmos_endpoint
    COSMOS_DATABASE      = "dronedelivery"
    REDIS_HOST           = module.data.redis_hostname
    REDIS_PORT           = tostring(module.data.redis_ssl_port)
    REDIS_SSL            = "true"
    STORAGE_ACCOUNT      = module.data.storage_account_name
    KEYVAULT_ENDPOINT    = module.platform.key_vault_uri
  }

  apps = {
    ingestion = {
      public        = true, identity_key = "ingestion"
      instances_min = var.instances_ingestion, cpu = "1", memory = "2Gi"
    }
    workflow = {
      public        = false, identity_key = "workflow"
      instances_min = var.instances_workflow, cpu = "1", memory = "2Gi"
    }
    delivery = {
      public        = true, identity_key = "delivery"
      instances_min = var.instances_delivery, cpu = "1", memory = "2Gi"
    }
    package = {
      public        = false, identity_key = "package"
      instances_min = var.instances_package, cpu = "500m", memory = "1Gi"
    }
    "drone-scheduler" = {
      public        = false, identity_key = "dronesched"
      instances_min = var.instances_dronesched, cpu = "1", memory = "2Gi"
    }
    "delivery-history" = {
      public        = true, identity_key = "history"
      instances_min = var.instances_history, cpu = "1", memory = "2Gi"
    }
  }

  tags = module.naming.tags
}
