variable "system" {
  description = "시스템 식별자 (소문자·하이픈)"
  type        = string
  default     = "drone"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.system))
    error_message = "system 은 소문자·숫자·하이픈으로 2~12자여야 합니다."
  }
}

variable "env" {
  description = "환경 — dev | stg | prd"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prd"], var.env)
    error_message = "env 는 dev · stg · prd 중 하나여야 합니다."
  }
}

variable "region_short" {
  description = "지역 약어 (예: krc = koreacentral)"
  type        = string
  default     = "krc"
}

variable "owner" {
  description = "담당자 — 비용 추적과 문의처"
  type        = string
}

variable "cost_center" {
  description = "비용 센터"
  type        = string
  default     = "training"
}

variable "deployed_at" {
  description = "배포 시각 — 파이프라인이 주입한다. timestamp() 를 쓰면 드리프트가 생긴다."
  type        = string
  default     = "unset"
}

variable "apps" {
  description = "애플리케이션 목록 — 앱별 관리 ID 이름을 만든다"
  type        = list(string)
  default     = ["ingestion", "workflow", "delivery", "package", "dronesched", "history"]
}

variable "extra_tags" {
  description = "추가 태그"
  type        = map(string)
  default     = {}
}
