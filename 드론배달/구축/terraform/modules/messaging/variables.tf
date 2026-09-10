variable "service_bus_name" { type = string }
variable "event_hubs_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "service_bus_sku" {
  description = "Basic | Standard | Premium. Premium 만 프라이빗 엔드포인트 지원"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "service_bus_sku 는 Basic · Standard · Premium 중 하나여야 합니다."
  }
}

variable "service_bus_local_auth_enabled" {
  description = "SAS 키 인증 허용 여부. false 여야 «비밀 없음»이 성립한다"
  type        = bool
  default     = false
}

variable "eventhub_local_auth_enabled" {
  type    = bool
  default = false
}

variable "event_hubs_sku" {
  type    = string
  default = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.event_hubs_sku)
    error_message = "event_hubs_sku 는 Basic · Standard · Premium 중 하나여야 합니다."
  }
}

variable "event_hubs_capacity" {
  description = "처리량 단위(TU)"
  type        = number
  default     = 1
}

variable "event_hubs_max_capacity" {
  description = "자동 팽창 최대 TU"
  type        = number
  default     = 4
}

variable "delivery_tracking_partitions" {
  type    = number
  default = 4
}

variable "drone_status_partitions" {
  description = "드론 텔레메트리 파티션 — prd 는 16 (NFR-04)"
  type        = number
  default     = 8
}

variable "retention_days" {
  type    = number
  default = 3
}

variable "public_network_access" {
  description = "공용 네트워크 접근. stg·prd 는 false"
  type        = bool
  default     = true
}

variable "tags" { type = map(string) }
