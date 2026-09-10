# 상태 저장소 부트스트랩 — 딱 한 번만 실행한다.
#
# ⚠️ 이 구성만 «로컬 상태»를 쓴다. 상태를 저장할 곳을 만드는 중이므로
#    원격 상태를 쓸 수 없다 (닭과 달걀).
#
# 실행 후 생성되는 Storage 계정을 각 환경의 backend.tf 가 참조한다.

terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.system}-tfstate"
  location = var.location

  tags = {
    system    = var.system
    purpose   = "terraform-state"
    managedBy = "terraform"
    owner     = var.owner
  }
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "st${var.system}tfstate"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "GRS" # 상태 소실 = 인프라 통제 상실

  # ⚠️ 상태 파일에는 비밀이 평문으로 남을 수 있다.
  #    이 저장소를 «비밀처럼» 다뤄야 한다.
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # ⛔ 공유 키 접근 차단 — Entra 인증만 허용 (backend 의 use_azuread_auth 와 짝).
  shared_access_key_enabled = false

  blob_properties {
    # 상태가 손상되면 이전 버전으로 되돌린다.
    versioning_enabled = true

    delete_retention_policy {
      days = 90
    }

    container_delete_retention_policy {
      days = 90
    }
  }

  tags = {
    system    = var.system
    purpose   = "terraform-state"
    managedBy = "terraform"
    owner     = var.owner
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# 실수로 지우지 못하게 잠근다.
resource "azurerm_management_lock" "tfstate" {
  name       = "lock-tfstate"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Terraform 상태 저장소 — 삭제하면 모든 환경의 인프라 통제를 잃습니다."
}

output "backend_config" {
  description = "각 환경의 backend.tf 에 넣을 값"
  value = {
    resource_group_name  = azurerm_resource_group.tfstate.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
    use_azuread_auth     = true
  }
}
