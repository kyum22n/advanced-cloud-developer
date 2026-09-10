# 관측성 — Log Analytics + Application Insights.
#
# 두 리소스를 «먼저» 만드는 이유 — 다른 모든 리소스의 진단 설정이 이것을 참조한다.
# 나중에 붙이면 «그동안의 로그가 없는» 구간이 생긴다.

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = var.app_insights_name
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "java"

  # 샘플링 — prd 10%, stg 50%, dev 100% (설계/10 §5.2)
  # ⚠️ 오류와 느린 요청은 애플리케이션 쪽에서 항상 수집하도록 별도 구성한다.
  #    오류를 샘플링하면 가장 중요한 것을 잃는다.
  sampling_percentage = var.sampling_percentage

  tags = var.tags
}

# ─────────────────────────────────────────── 예산 경고
#
# 비용은 «나중에 청구서를 보고» 알면 늦다. 예산의 80%·100% 에서 알린다.

resource "azurerm_consumption_budget_resource_group" "main" {
  count = var.monthly_budget_amount > 0 ? 1 : 0

  name              = "budget-${var.name_suffix}"
  resource_group_id = var.resource_group_id

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }
}
