output "identity_ids" {
  description = "관리 ID 리소스 ID — Spring Apps 에 연결한다"
  value       = { for k, i in azurerm_user_assigned_identity.apps : k => i.id }
}

output "client_ids" {
  description = "클라이언트 ID — 앱의 AZURE_CLIENT_ID 환경 변수로 주입한다"
  value       = { for k, i in azurerm_user_assigned_identity.apps : k => i.client_id }
}

output "principal_ids" {
  value = { for k, i in azurerm_user_assigned_identity.apps : k => i.principal_id }
}
