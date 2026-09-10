output "redis_hostname" {
  value = azurerm_redis_cache.main.hostname
}

output "redis_ssl_port" {
  value = azurerm_redis_cache.main.ssl_port
}

output "redis_id" {
  value = azurerm_redis_cache.main.id
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.nosql.endpoint
}

output "cosmos_account_id" {
  value = azurerm_cosmosdb_account.nosql.id
}

output "cosmos_account_name" {
  value = azurerm_cosmosdb_account.nosql.name
}

output "cosmos_mongo_account_name" {
  value = azurerm_cosmosdb_account.mongo.name
}

output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

output "storage_account_id" {
  value = azurerm_storage_account.lake.id
}

output "history_container_id" {
  value = azurerm_storage_container.history.id
}

output "storage_primary_web_endpoint" {
  value = azurerm_storage_account.lake.primary_web_endpoint
}
