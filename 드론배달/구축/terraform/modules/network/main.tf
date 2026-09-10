# 네트워크 — 허브‑스포크 스포크 측.
#
# dev 는 VNet 없이 공용 엔드포인트를 쓴다(비용·단순성).
# stg·prd 는 VNet 주입 + 프라이빗 엔드포인트를 쓴다.
#
# ⚠️ dev 와 prd 의 «기능» 차이가 아니라 «규모·격리 수준» 차이만 두는 것이 원칙이지만,
#    네트워크는 예외적으로 구조가 다르다. 그래서 dev 에서 못 잡는 문제가 있다는 것을
#    알고 있어야 하고, stg 가 prd 와 같은 네트워크 구조를 갖는 이유가 그것이다.

resource "azurerm_virtual_network" "spoke" {
  count = var.enabled ? 1 : 0

  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "appgw" {
  count = var.enabled ? 1 : 0

  name                 = "snet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[0].name
  address_prefixes     = [cidrsubnet(var.address_space, 8, 0)]
}

resource "azurerm_subnet" "runtime" {
  count = var.enabled ? 1 : 0

  name                 = "snet-runtime"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[0].name
  address_prefixes     = [cidrsubnet(var.address_space, 8, 1)]
}

resource "azurerm_subnet" "apps" {
  count = var.enabled ? 1 : 0

  name                 = "snet-apps"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[0].name
  address_prefixes     = [cidrsubnet(var.address_space, 8, 2)]
}

resource "azurerm_subnet" "private_endpoints" {
  count = var.enabled ? 1 : 0

  name                 = "snet-pe"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke[0].name
  address_prefixes     = [cidrsubnet(var.address_space, 8, 3)]

  private_endpoint_network_policies = "Enabled"
}

# ─────────────────────────────────────────── NSG
#
# 제로 트러스트 — 기본은 «전부 거부»이고, 필요한 것만 명시적으로 연다 (SEC-03).

resource "azurerm_network_security_group" "apps" {
  count = var.enabled ? 1 : 0

  name                = "nsg-apps-${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_network_security_rule" "apps_allow_appgw" {
  count = var.enabled ? 1 : 0

  name                        = "allow-appgw-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["8080", "8081", "8083", "8086"]
  source_address_prefix       = azurerm_subnet.appgw[0].address_prefixes[0]
  destination_address_prefix  = azurerm_subnet.apps[0].address_prefixes[0]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apps[0].name
}

resource "azurerm_network_security_rule" "apps_allow_pe" {
  count = var.enabled ? 1 : 0

  name                        = "allow-private-endpoints-outbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["443", "6380", "10000", "10255"]
  source_address_prefix       = azurerm_subnet.apps[0].address_prefixes[0]
  destination_address_prefix  = azurerm_subnet.private_endpoints[0].address_prefixes[0]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apps[0].name
}

resource "azurerm_network_security_rule" "apps_allow_monitor" {
  count = var.enabled ? 1 : 0

  name                        = "allow-azure-monitor-outbound"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = azurerm_subnet.apps[0].address_prefixes[0]
  destination_address_prefix  = "AzureMonitor"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apps[0].name
}

# ★ 마지막 방어선 — 명시적 거부.
#   Azure 기본 규칙(65000번대)이 인터넷 아웃바운드를 허용하므로,
#   그보다 낮은 우선순위로 명시적 거부를 두어야 실제로 막힌다.
resource "azurerm_network_security_rule" "apps_deny_internet_outbound" {
  count = var.enabled ? 1 : 0

  name                        = "deny-internet-outbound"
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apps[0].name
}

resource "azurerm_network_security_rule" "apps_deny_all_inbound" {
  count = var.enabled ? 1 : 0

  name                        = "deny-all-inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apps[0].name
}

resource "azurerm_subnet_network_security_group_association" "apps" {
  count = var.enabled ? 1 : 0

  subnet_id                 = azurerm_subnet.apps[0].id
  network_security_group_id = azurerm_network_security_group.apps[0].id
}

# ─────────────────────────────────────────── 허브 피어링 (prd 만)

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count = var.enabled && var.hub_vnet_id != null ? 1 : 0

  name                      = "peer-spoke-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.spoke[0].name
  remote_virtual_network_id = var.hub_vnet_id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

# ─────────────────────────────────────────── 프라이빗 DNS 영역

locals {
  private_dns_zones = var.enabled ? {
    servicebus = "privatelink.servicebus.windows.net"
    cosmos     = "privatelink.documents.azure.com"
    mongo      = "privatelink.mongo.cosmos.azure.com"
    redis      = "privatelink.redis.azure.net"
    keyvault   = "privatelink.vaultcore.azure.net"
    blob       = "privatelink.blob.core.windows.net"
    acr        = "privatelink.azurecr.io"
  } : {}
}

resource "azurerm_private_dns_zone" "zones" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each = local.private_dns_zones

  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = azurerm_virtual_network.spoke[0].id
  registration_enabled  = false
  tags                  = var.tags
}
