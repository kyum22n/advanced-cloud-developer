output "container_registry_id" {
  value = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}
