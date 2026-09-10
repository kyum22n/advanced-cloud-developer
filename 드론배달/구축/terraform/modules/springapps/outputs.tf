output "service_id" {
  value = azurerm_spring_cloud_service.main.id
}

output "app_ids" {
  value = { for k, a in azurerm_spring_cloud_app.apps : k => a.id }
}

output "app_urls" {
  description = "공개 앱의 URL. 비공개 앱은 null"
  value       = { for k, a in azurerm_spring_cloud_app.apps : k => a.url }
}

output "outbound_public_ips" {
  value = azurerm_spring_cloud_service.main.outbound_public_ip_addresses
}
