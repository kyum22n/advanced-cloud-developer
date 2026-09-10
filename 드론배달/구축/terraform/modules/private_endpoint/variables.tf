variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "target_resource_id" { type = string }
variable "private_dns_zone_id" { type = string }

variable "subresource_names" {
  description = "예: [\"namespace\"] · [\"Sql\"] · [\"redisCache\"] · [\"vault\"] · [\"blob\"] · [\"registry\"]"
  type        = list(string)
}

variable "tags" { type = map(string) }
