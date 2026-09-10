variable "identity_names" {
  description = "앱 키 → 관리 ID 이름"
  type        = map(string)
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "service_bus_queue_id" {
  type    = string
  default = null
}

variable "eventhub_delivery_tracking_id" {
  type    = string
  default = null
}

variable "eventhub_drone_status_id" {
  type    = string
  default = null
}

variable "storage_container_id" {
  type    = string
  default = null
}

variable "cosmos_account_id" {
  type    = string
  default = null
}

variable "cosmos_account_name" {
  type    = string
  default = null
}

variable "container_registry_id" {
  type    = string
  default = null
}

variable "tags" {
  type = map(string)
}
