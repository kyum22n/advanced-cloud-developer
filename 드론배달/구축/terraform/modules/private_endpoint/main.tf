# 프라이빗 엔드포인트 — PaaS 를 공용 인터넷에서 떼어낸다 (SEC-06).
#
# 이것이 없으면 «방화벽으로 IP 를 막는» 방식에 의존하게 되는데,
# 그 방식은 규칙이 늘수록 관리가 어렵고 실수 한 번에 노출된다.
# 프라이빗 엔드포인트는 «애초에 공용 주소가 없는» 상태를 만든다.

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = var.subresource_names
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}
