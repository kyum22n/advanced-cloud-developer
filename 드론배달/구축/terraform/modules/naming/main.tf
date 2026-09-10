# 리소스 이름 생성 — 규칙을 코드로 강제한다.
#
# 이름을 손으로 지으면 «rg-drone-prod» 와 «rg-drone-prd» 가 섞이고,
# 나중에 스크립트로 찾을 수 없게 된다. 규칙을 한곳에 두면 그런 일이 없다.

locals {
  # 접두사: {system}-{env}-{region}
  prefix = "${var.system}-${var.env}-${var.region_short}"

  # 하이픈·대문자를 허용하지 않는 리소스용 (Storage · ACR)
  compact = lower(replace("${var.system}${var.env}${var.region_short}", "-", ""))
}

output "prefix" {
  description = "공통 접두사"
  value       = local.prefix
}

output "resource_group" {
  value = "rg-${local.prefix}"
}

output "vnet" {
  value = "vnet-${local.prefix}"
}

output "spring_apps" {
  value = "asa-${local.prefix}"
}

output "app_gateway" {
  value = "agw-${local.prefix}"
}

output "front_door" {
  value = "afd-${local.prefix}"
}

output "firewall" {
  value = "afw-${local.prefix}"
}

output "service_bus" {
  value = "sb-${local.prefix}"
}

output "event_hubs" {
  value = "evhns-${local.prefix}"
}

output "redis" {
  value = "redis-${local.prefix}"
}

output "cosmos" {
  value = "cosmos-${local.prefix}"
}

output "cosmos_mongo" {
  value = "mongo-${local.prefix}"
}

# Key Vault 는 24자 제한이 있다 — 접두사를 압축해서 쓴다.
output "key_vault" {
  value = substr("kv-${local.compact}", 0, 24)
}

# Container Registry 는 영숫자만 허용한다.
output "container_registry" {
  value = substr("acr${local.compact}", 0, 50)
}

# Storage 계정은 영숫자 24자.
output "storage" {
  value = substr("st${local.compact}", 0, 24)
}

output "log_analytics" {
  value = "log-${local.prefix}"
}

output "app_insights" {
  value = "appi-${local.prefix}"
}

# 앱별 관리 ID 이름 — 하나의 앱 = 하나의 ID (설계/09 §4)
output "identity_names" {
  value = {
    for app in var.apps : app => "id-${var.system}-${app}-${var.env}"
  }
}

# 모든 리소스에 붙는 태그.
# ⚠️ timestamp() 를 쓰지 않는다 — plan 마다 값이 바뀌어 전 리소스가 변경 대상이 된다.
output "tags" {
  value = merge({
    system     = var.system
    env        = var.env
    owner      = var.owner
    costCenter = var.cost_center
    managedBy  = "terraform"
    deployedAt = var.deployed_at
  }, var.extra_tags)
}
