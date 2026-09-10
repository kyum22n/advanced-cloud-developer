output "public_ip" {
  value = var.enabled ? azurerm_public_ip.appgw[0].ip_address : null
}

output "gateway_id" {
  value = var.enabled ? azurerm_application_gateway.main[0].id : null
}
