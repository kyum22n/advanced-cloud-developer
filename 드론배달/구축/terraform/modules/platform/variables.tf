variable "container_registry_name" { type = string }
variable "key_vault_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }

variable "acr_sku" {
  description = "Basic | Standard | Premium. 프라이빗 엔드포인트는 Premium 필요"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku 는 Basic · Standard · Premium 중 하나여야 합니다."
  }
}

variable "public_network_access" {
  type    = bool
  default = true
}

variable "purge_protection_enabled" {
  description = "영구 삭제 방지. prd 는 true — 켜면 되돌릴 수 없으므로 dev 는 false"
  type        = bool
  default     = false
}

variable "secret_reader_principal_ids" {
  description = "Key Vault 비밀을 읽을 관리 ID 의 principal ID"
  type        = map(string)
  default     = {}
}

variable "tags" { type = map(string) }
