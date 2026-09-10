variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "env" { type = string }

variable "sku" {
  description = "Basic | Standard | Enterprise"
  type        = string
  default     = "S0"
}

variable "vnet_injection" {
  description = "VNet 주입 여부. dev 는 false"
  type        = bool
  default     = false
}

variable "app_subnet_id" {
  type    = string
  default = null
}
variable "runtime_subnet_id" {
  type    = string
  default = null
}

variable "service_cidr_ranges" {
  description = "Spring Apps 내부용 CIDR 3개. VNet 주소 공간과 겹치면 안 된다"
  type        = list(string)
  default     = ["10.240.0.0/16", "10.243.0.0/16", "172.30.0.0/16"]
}

variable "apps" {
  description = <<-EOT
    애플리케이션 정의.
      public        공개 엔드포인트 노출 여부
      identity_key  사용할 관리 ID 키
      instances_min 초기 인스턴스 수 (자동 확장 하한)
      cpu / memory  리소스 할당
  EOT
  type = map(object({
    public                = bool
    identity_key          = string
    instances_min         = number
    cpu                   = string
    memory                = string
    environment_variables = optional(map(string), {})
  }))
}

variable "identity_ids" {
  description = "관리 ID 키 → 리소스 ID"
  type        = map(string)
}

variable "client_ids" {
  description = "관리 ID 키 → 클라이언트 ID"
  type        = map(string)
}

variable "common_environment_variables" {
  description = "모든 앱에 공통으로 주입할 환경 변수 (엔드포인트 등). ⛔ 비밀은 넣지 않는다"
  type        = map(string)
  default     = {}
}

variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "trace_sample_rate" {
  description = "분산 추적 샘플링 (0.0 ~ 100.0)"
  type        = number
  default     = 100.0
}

variable "config_repo_uri" {
  description = "구성 서버 Git 저장소. null 이면 구성 서버를 쓰지 않는다"
  type        = string
  default     = null
}

variable "config_repo_label" {
  type    = string
  default = "main"
}

variable "config_repo_search_paths" {
  type    = list(string)
  default = ["config"]
}

variable "tags" { type = map(string) }
