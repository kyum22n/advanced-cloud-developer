variable "enabled" {
  description = "게이트웨이를 만들 것인가. dev 는 false"
  type        = bool
  default     = true
}

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }

variable "waf_mode" {
  description = "Detection(감지) | Prevention(차단). stg 는 Detection 부터 시작한다"
  type        = string
  default     = "Detection"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode 는 Detection 또는 Prevention 이어야 합니다."
  }
}

variable "enable_rate_limit" {
  type    = bool
  default = true
}

variable "rate_limit_per_minute" {
  description = "IP 당 분당 요청 한도"
  type        = number
  default     = 5000
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 10
}

variable "zone_redundant" {
  type    = bool
  default = false
}

variable "backends" {
  description = "백엔드 키 → { fqdn }"
  type        = map(object({ fqdn = string }))
}

variable "default_backend" {
  description = "경로가 매칭되지 않을 때 보낼 백엔드 키"
  type        = string
}

variable "path_rules" {
  description = "규칙 이름 → { paths, backend }"
  type = map(object({
    paths   = list(string)
    backend = string
  }))
}

variable "tls_certificate_key_vault_id" {
  description = "Key Vault 인증서 비밀 ID. 파일로 두지 않는다"
  type        = string
}

variable "gateway_identity_id" {
  description = "게이트웨이가 Key Vault 를 읽는 데 쓸 관리 ID"
  type        = string
}

variable "tags" { type = map(string) }
