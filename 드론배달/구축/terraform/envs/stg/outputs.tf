# 환경 출력 — 배포 스크립트와 검증 스크립트가 읽는다.
#
# ⚠️ 비밀은 sensitive 로 표시하고, 되도록 출력하지 않는다.
#    `terraform output -json` 결과가 파일로 남으면 그것도 비밀 저장소다.

output "environment" {
  value = "stg"
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "location" {
  value = var.location
}

output "spring_apps_name" {
  value = module.spring_apps.service_id
}

output "app_urls" {
  description = "공개 앱 URL"
  value       = module.spring_apps.app_urls
}

output "service_bus_namespace" {
  value = module.messaging.service_bus_namespace
}

output "event_hubs_namespace" {
  value = module.messaging.event_hubs_namespace
}

output "cosmos_endpoint" {
  value = module.data.cosmos_endpoint
}

output "redis_hostname" {
  value = module.data.redis_hostname
}

output "storage_account" {
  value = module.data.storage_account_name
}

output "container_registry" {
  value = module.platform.container_registry_login_server
}

output "key_vault_uri" {
  value = module.platform.key_vault_uri
}

output "identity_client_ids" {
  description = "앱별 관리 ID 클라이언트 ID — 검증 스크립트가 쓴다"
  value       = module.identity.client_ids
}

output "vnet_id" {
  value = module.network.vnet_id
}

output "app_insights_connection_string" {
  value     = module.observability.app_insights_connection_string
  sensitive = true
}
