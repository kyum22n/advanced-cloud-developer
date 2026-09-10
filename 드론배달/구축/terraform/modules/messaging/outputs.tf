output "service_bus_namespace" {
  value = azurerm_servicebus_namespace.main.name
}

output "service_bus_fqdn" {
  value = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
}

output "service_bus_namespace_id" {
  value = azurerm_servicebus_namespace.main.id
}

output "delivery_requests_queue_id" {
  value = azurerm_servicebus_queue.delivery_requests.id
}

output "event_hubs_namespace" {
  value = azurerm_eventhub_namespace.main.name
}

output "event_hubs_namespace_id" {
  value = azurerm_eventhub_namespace.main.id
}

output "delivery_tracking_id" {
  value = azurerm_eventhub.delivery_tracking.id
}

output "drone_status_id" {
  value = azurerm_eventhub.drone_status.id
}
