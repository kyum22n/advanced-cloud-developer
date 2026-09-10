variable "redis_name" { type = string }
variable "cosmos_name" { type = string }
variable "cosmos_mongo_name" { type = string }
variable "storage_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "redis_sku" {
  description = "Basic | Standard | Premium"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.redis_sku)
    error_message = "redis_sku 는 Basic · Standard · Premium 중 하나여야 합니다."
  }
}

variable "redis_family" {
  description = "C = Basic/Standard, P = Premium"
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  type    = number
  default = 1
}

variable "cosmos_serverless" {
  description = "서버리스 모드. dev 에서 비용을 크게 줄인다"
  type        = bool
  default     = false
}

variable "cosmos_max_throughput" {
  description = "자동 확장 최대 RU/s"
  type        = number
  default     = 1000

  validation {
    condition     = var.cosmos_max_throughput >= 1000 && var.cosmos_max_throughput % 1000 == 0
    error_message = "최대 처리량은 1000 이상이고 1000의 배수여야 합니다."
  }
}

variable "cosmos_local_auth_disabled" {
  description = "계정 키 비활성. true 여야 «비밀 없음»이 성립한다"
  type        = bool
  default     = true
}

variable "storage_replication" {
  description = "LRS | ZRS | GRS"
  type        = string
  default     = "LRS"
}

variable "storage_shared_key_enabled" {
  description = "공유 키 접근. false 여야 관리 ID 만 허용된다"
  type        = bool
  default     = false
}

variable "public_network_access" {
  type    = bool
  default = true
}

variable "enable_zone_redundancy" {
  type    = bool
  default = false
}

variable "availability_zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "tags" { type = map(string) }
