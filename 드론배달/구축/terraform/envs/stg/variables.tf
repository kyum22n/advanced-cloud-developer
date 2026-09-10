# 환경 변수 정의.
#
# 기본값은 «가장 안전하고 가장 저렴한» 쪽으로 둔다.
# 값을 올리는 것은 의식적인 선택이어야 하고, 내리는 것은 실수여도 안전해야 한다.

variable "subscription_id" {
  description = "Azure 구독 ID"
  type        = string
}

variable "system" {
  type    = string
  default = "drone"
}

variable "location" {
  type    = string
  default = "koreacentral"
}

variable "region_short" {
  type    = string
  default = "krc"
}

variable "owner" {
  description = "담당자 — 태그와 예산 알림에 쓰인다"
  type        = string
}

variable "cost_center" {
  type    = string
  default = "training"
}

variable "deployed_at" {
  description = "배포 시각. 파이프라인이 주입한다"
  type        = string
  default     = "unset"
}

# ── 네트워크
variable "vnet_enabled" {
  type    = bool
  default = false
}

variable "vnet_address_space" {
  type    = string
  default = "10.3.0.0/16"
}

variable "hub_vnet_id" {
  type    = string
  default = null
}

variable "public_network_access" {
  description = "PaaS 공용 네트워크 접근. stg·prd 는 false"
  type        = bool
  default     = true
}

# ── 플랫폼
variable "acr_sku" {
  type    = string
  default = "Basic"
}

variable "key_vault_purge_protection" {
  description = "영구 삭제 방지. 켜면 되돌릴 수 없으므로 dev 는 false"
  type        = bool
  default     = false
}

# ── 메시징
variable "service_bus_sku" {
  type    = string
  default = "Basic"
}
variable "event_hubs_sku" {
  type    = string
  default = "Basic"
}
variable "event_hubs_capacity" {
  type    = number
  default = 1
}
variable "event_hubs_max_capacity" {
  type    = number
  default = 1
}
variable "delivery_tracking_partitions" {
  type    = number
  default = 2
}
variable "drone_status_partitions" {
  type    = number
  default = 2
}
variable "eventhub_retention_days" {
  type    = number
  default = 1
}

# ── 데이터
variable "redis_sku" {
  type    = string
  default = "Basic"
}
variable "redis_family" {
  type    = string
  default = "C"
}
variable "redis_capacity" {
  type    = number
  default = 0
}
variable "cosmos_serverless" {
  type    = bool
  default = true
}
variable "cosmos_max_throughput" {
  type    = number
  default = 1000
}
variable "storage_replication" {
  type    = string
  default = "LRS"
}
variable "enable_zone_redundancy" {
  type    = bool
  default = false
}

# ── 컴퓨팅
variable "spring_apps_sku" {
  type    = string
  default = "S0"
}
variable "instances_ingestion" {
  type    = number
  default = 1
}
variable "instances_workflow" {
  type    = number
  default = 1
}
variable "instances_delivery" {
  type    = number
  default = 1
}
variable "instances_package" {
  type    = number
  default = 1
}
variable "instances_dronesched" {
  type    = number
  default = 1
}
variable "instances_history" {
  type    = number
  default = 1
}

# ── 관측성
variable "log_retention_days" {
  type    = number
  default = 30
}

variable "trace_sampling_percentage" {
  description = "dev 100 · stg 50 · prd 10. 오류는 애플리케이션에서 항상 수집한다"
  type        = number
  default     = 100
}

variable "monthly_budget_amount" {
  type    = number
  default = 0
}

variable "budget_start_date" {
  type    = string
  default = "2026-09-01T00:00:00Z"
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}
