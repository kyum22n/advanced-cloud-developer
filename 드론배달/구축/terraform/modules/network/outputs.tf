output "vnet_id" {
  value = var.enabled ? azurerm_virtual_network.spoke[0].id : null
}

output "subnet_appgw_id" {
  value = var.enabled ? azurerm_subnet.appgw[0].id : null
}

output "subnet_runtime_id" {
  value = var.enabled ? azurerm_subnet.runtime[0].id : null
}

output "subnet_apps_id" {
  value = var.enabled ? azurerm_subnet.apps[0].id : null
}

output "subnet_pe_id" {
  value = var.enabled ? azurerm_subnet.private_endpoints[0].id : null
}

output "private_dns_zone_ids" {
  description = "프라이빗 엔드포인트가 참조할 DNS 영역 ID"
  value       = { for k, z in azurerm_private_dns_zone.zones : k => z.id }
}
