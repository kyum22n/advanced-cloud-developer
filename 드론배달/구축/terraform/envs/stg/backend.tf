terraform {
  backend "azurerm" {
    resource_group_name  = "rg-drone-tfstate"
    storage_account_name = "stdronetfstate"
    container_name       = "tfstate"
    key                  = "stg.terraform.tfstate"

    # ★ 스토리지 키 대신 Entra 인증 — 부트스트랩에서 공유 키를 껐기 때문에 필수다.
    use_azuread_auth = true
  }
}
