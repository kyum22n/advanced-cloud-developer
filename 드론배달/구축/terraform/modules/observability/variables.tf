variable "log_analytics_name" {
  type = string
}

variable "app_insights_name" {
  type = string
}

variable "name_suffix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "location" {
  type = string
}

variable "retention_days" {
  description = "로그 보존 일수 — dev 30 · prd 90"
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 30 && var.retention_days <= 730
    error_message = "보존 기간은 30 ~ 730일이어야 합니다."
  }
}

variable "sampling_percentage" {
  description = "추적 샘플링 비율 — dev 100 · stg 50 · prd 10"
  type        = number
  default     = 100

  validation {
    condition     = var.sampling_percentage > 0 && var.sampling_percentage <= 100
    error_message = "샘플링 비율은 0 초과 100 이하여야 합니다."
  }
}

variable "monthly_budget_amount" {
  description = "월 예산 (통화 단위). 0 이면 예산을 만들지 않는다"
  type        = number
  default     = 0
}

variable "budget_start_date" {
  description = "예산 시작일 (YYYY-MM-01T00:00:00Z)"
  type        = string
  default     = "2026-09-01T00:00:00Z"
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}

variable "tags" {
  type = map(string)
}
