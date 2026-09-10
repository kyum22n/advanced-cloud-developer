variable "enabled" {
  description = "VNet 을 만들 것인가. dev 는 false (공용 엔드포인트 사용)"
  type        = bool
  default     = true
}

variable "vnet_name" {
  type = string
}

variable "name_suffix" {
  description = "NSG 등 부가 리소스 이름에 붙일 접미사"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  description = "VNet 주소 공간 (/16 권장)"
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0))
    error_message = "address_space 는 유효한 CIDR 이어야 합니다."
  }
}

variable "hub_vnet_id" {
  description = "허브 VNet 리소스 ID. null 이면 피어링하지 않는다 (dev·stg)"
  type        = string
  default     = null
}

variable "tags" {
  type = map(string)
}
