variable "resource_group_name" {}
variable "location" {}

provider "azurerm" {
  version = "=2.40.0"
  features {}
}

resource "random_string" "uniqstr" {
  length  = 6
  special = false
  upper   = false
  keepers = {
    resource_group_name = var.resource_group_name
  }
}
module "resource_group" {
  source   = "./modules/resource_group"
  location = var.location
  name     = var.resource_group_name
}
module "acr" {
  source              = "./modules/acr"
  name                = "acrtsunomuraksdemo${random_string.uniqstr.result}"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = "Basic"
  admin               = false
  geo_replication     = null
}
module "la" {
  source              = "./modules/log_analytics"
  name                = "la-aksdemo${random_string.uniqstr.result}"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = null
  retention           = null
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-aksdemo"
  address_space       = ["10.0.0.0/8"]
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
}

resource "azurerm_subnet" "subnet-default" {
  name                 = "default"
  resource_group_name  = module.resource_group.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
  service_endpoints    = ["Microsoft.Sql"]
}
resource "azurerm_subnet" "subnet-aks" {
  name                 = "aks"
  resource_group_name  = module.resource_group.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Sql"]
}
resource "azurerm_subnet" "subnet-apim" {
  name                 = "apim"
  resource_group_name  = module.resource_group.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
resource "azurerm_subnet" "subnet-appgw" {
  name                 = "appgw"
  resource_group_name  = module.resource_group.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

###################
# VM
###################
module "linux-vm" {
  source              = "./modules/virtualmachine/linux"
  admin_username      = "adminuser"
  admin_password      = "pn,i86*3+R"
  name                = "VM2"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  subnet_id           = azurerm_subnet.subnet-default.id
  zone                = 2
  custom_data         = <<EOF
#!/bin/bash
sudo apt-get update
sudo apt-get install nginx -y
curl -sL https://releases.rancher.com/install-docker/19.03.sh | sh
EOF
}

module "windows-vm" {
  source              = "./modules/virtualmachine/windows"
  admin_username      = "adminuser"
  admin_password      = "pn,i86*3+R"
  name                = "VM1"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  subnet_id           = azurerm_subnet.subnet-default.id
  zone                = 1
}

###################
# Load Balancer
###################
resource "azurerm_public_ip" "aksdemo" {
  name                = "pip-lb-aksdemo"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_lb" "aksdemo" {
  name                = "lb-aksdemo"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = "Standard"
  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.aksdemo.id
  }
}

resource "azurerm_lb_backend_address_pool" "aksdemo" {
  resource_group_name = module.resource_group.name
  loadbalancer_id     = azurerm_lb.aksdemo.id
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_rule" "aksdemo" {
  resource_group_name            = module.resource_group.name
  loadbalancer_id                = azurerm_lb.aksdemo.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = azurerm_lb.aksdemo.frontend_ip_configuration[0].name
  backend_address_pool_id        = azurerm_lb_backend_address_pool.aksdemo.id
  probe_id                       = azurerm_lb_probe.aksdemo.id
}

resource "azurerm_lb_probe" "aksdemo" {
  resource_group_name = module.resource_group.name
  loadbalancer_id     = azurerm_lb.aksdemo.id
  name                = "nginx-running-probe"
  port                = 80
  protocol            = "Http"
  request_path        = "/"
  interval_in_seconds = 5
  number_of_probes    = 3
}

resource "azurerm_network_interface_backend_address_pool_association" "aksdemo" {
  network_interface_id    = module.linux-vm.nic_id
  ip_configuration_name   = module.linux-vm.ip_configuration_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.aksdemo.id
}

###################
# AKS
###################
module "demo-aks" {
  source                     = "./modules/aks"
  name                       = "aksdemo${random_string.uniqstr.result}"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_registry_id      = module.acr.id
  log_analytics_workspace_id = module.la.id
  kubernetes_version         = "1.19.3"
  private_cluster            = false
  default_node_pool = {
    name                           = "nodepool"
    node_count                     = 1
    vm_size                        = "Standard_B2s"
    zones                          = ["1", "2", "3"]
    labels                         = null
    taints                         = null
    cluster_auto_scaling           = false
    cluster_auto_scaling_max_count = null
    cluster_auto_scaling_min_count = null
  }
  addons = {
    oms_agent            = true
    kubernetes_dashboard = false
    azure_policy         = false
  }
  vnet_subnet_id        = azurerm_subnet.subnet-aks.id
  sla_sku               = null
  api_auth_ips          = null
  additional_node_pools = {}
  aad_group_name        = null
}

data "azurerm_monitor_diagnostic_categories" "aks-diag-categories" {
  resource_id = module.demo-aks.id
}

module "diag-aks" {
  source                     = "./modules/diagnostic_logs"
  name                       = "diag"
  target_resource_id         = module.demo-aks.id
  log_analytics_workspace_id = module.la.id
  diagnostic_logs            = data.azurerm_monitor_diagnostic_categories.aks-diag-categories.logs
  retention                  = 30
}

resource "azurerm_storage_account" "storage" {
  name                      = "sa${random_string.uniqstr.result}"
  resource_group_name       = module.resource_group.name
  location                  = module.resource_group.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  access_tier               = "Hot"
  enable_https_traffic_only = true
}

###################
# SQL Database
###################
resource "azurerm_sql_server" "sqlserver" {
  name                         = "sqldb${random_string.uniqstr.result}"
  resource_group_name          = module.resource_group.name
  location                     = module.resource_group.location
  version                      = "12.0"
  administrator_login          = "sqldbadmin"
  administrator_login_password = "Password1!"
}
resource "azurerm_sql_database" "sqldb" {
  name                = "aksdemo"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  server_name         = azurerm_sql_server.sqlserver.name
  edition             = "Basic"
}
resource "azurerm_sql_virtual_network_rule" "sqlserver-endpoint-aks" {
  name                = "from-aks-subnet"
  resource_group_name = module.resource_group.name
  server_name         = azurerm_sql_server.sqlserver.name
  subnet_id           = azurerm_subnet.subnet-aks.id
}
resource "azurerm_sql_virtual_network_rule" "sqlserver-endpoint-default" {
  name                = "from-default-subnet"
  resource_group_name = module.resource_group.name
  server_name         = azurerm_sql_server.sqlserver.name
  subnet_id           = azurerm_subnet.subnet-default.id
}


###################
# API Management
###################
resource "azurerm_api_management" "aksdemo" {
  name                = "apim-aksdemo${random_string.uniqstr.result}"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  publisher_name      = "Contoso"
  publisher_email     = "mail@contoso.com"

  sku_name = "Developer_1"

  virtual_network_type = "Internal"
  virtual_network_configuration {
    subnet_id = azurerm_subnet.subnet-apim.id
  }
}
resource "azurerm_private_dns_zone" "apim" {
  name                = "azure-api.net"
  resource_group_name = module.resource_group.name
}
resource "azurerm_private_dns_a_record" "apim" {
  for_each = toset([
    azurerm_api_management.aksdemo.name,
    "${azurerm_api_management.aksdemo.name}.portal",
    "${azurerm_api_management.aksdemo.name}.developer",
    "${azurerm_api_management.aksdemo.name}.management",
    "${azurerm_api_management.aksdemo.name}.scm"

  ])
  name                = each.key
  zone_name           = azurerm_private_dns_zone.apim.name
  resource_group_name = module.resource_group.name
  ttl                 = 0
  records             = [azurerm_api_management.aksdemo.private_ip_addresses[0]]
}
resource "azurerm_private_dns_zone_virtual_network_link" "aksdemo" {
  name                  = "aksdemo"
  resource_group_name   = module.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.apim.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_api_management_api" "aksdemo" {
  name                  = "VM2"
  resource_group_name   = module.resource_group.name
  api_management_name   = azurerm_api_management.aksdemo.name
  revision              = "1"
  display_name          = "VM2"
  path                  = ""
  protocols             = ["http"]
  subscription_required = false

  service_url = "http://${module.linux-vm.private_ip_address}"

}
resource "azurerm_api_management_api_operation" "aksdemo" {
  operation_id        = "get-nginx"
  api_name            = azurerm_api_management_api.aksdemo.name
  api_management_name = azurerm_api_management.aksdemo.name
  resource_group_name = module.resource_group.name
  display_name        = "GET from nginx"
  method              = "GET"
  url_template        = "/"

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api" "sample-app" {
  name                  = "Uploader"
  resource_group_name   = module.resource_group.name
  api_management_name   = azurerm_api_management.aksdemo.name
  revision              = "1"
  display_name          = "Uploader"
  path                  = "uploader"
  protocols             = ["http"]
  subscription_required = false
  service_url           = "http://10.0.2.254/api"

  import {
    content_format = "openapi+json-link"
    content_value  = "https://raw.githubusercontent.com/hiroyha1/uploader/master/sample/api-docs.json"
  }

}
###################
# Application Gateway
###################
locals {
  appgw_name                           = "AppGW-aksdemo"
  appgw_backend_address_pool_name      = "BackEndPool1"
  appgw_frontend_port_name             = "appgw-fep"
  appgw_frontend_ip_name               = "AppGW-IP"
  appgw_frontend_ip_configuration_name = "appgw-ip-configuration"
  appgw_http_setting_name              = "HTTPSetting1"
  appgw_listener_name                  = "Listener1"
  appgw_request_routing_rule_name      = "Rule1"
  appgw_probe_name                     = "Probe1"
  appgw_probe_path                     = "/uploader/actuator/health"
}
resource "azurerm_public_ip" "appgw" {
  name                = local.appgw_frontend_ip_name
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku                 = "Standard"
  allocation_method   = "Static"
}
resource "azurerm_application_gateway" "aksdemo" {
  name                = local.appgw_name
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = local.appgw_frontend_ip_configuration_name
    subnet_id = azurerm_subnet.subnet-appgw.id
  }

  frontend_port {
    name = local.appgw_frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name  = local.appgw_backend_address_pool_name
    fqdns = ["${azurerm_api_management.aksdemo.name}.azure-api.net"]
  }

  backend_http_settings {
    name                                = local.appgw_http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 20
    probe_name                          = local.appgw_probe_name
    pick_host_name_from_backend_address = true
  }

  probe {
    name                                      = local.appgw_probe_name
    interval                                  = 10
    protocol                                  = "Http"
    path                                      = local.appgw_probe_path
    timeout                                   = 10
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }
  http_listener {
    name                           = local.appgw_listener_name
    frontend_ip_configuration_name = local.appgw_frontend_ip_configuration_name
    frontend_port_name             = local.appgw_frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.appgw_request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.appgw_listener_name
    backend_address_pool_name  = local.appgw_backend_address_pool_name
    backend_http_settings_name = local.appgw_http_setting_name
  }
}

###################
# Application Insights
###################
resource "azurerm_application_insights" "aksdemo" {
  name                = "appinsights-aksdemo"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  application_type    = "web"
}

###################
# Generate deployment.yaml
###################
locals {
  deployment_content = templatefile("${path.module}/deployment.yaml.tmpl", {
    STORAGE_CONNECTION_STRING             = azurerm_storage_account.storage.primary_connection_string
    DATABASE_URL                          = "jdbc:sqlserver://${azurerm_sql_server.sqlserver.name}.database.windows.net:1433;database=aksdemo;user=sqldbadmin@${azurerm_sql_server.sqlserver.name};password=Password1!;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.aksdemo.connection_string
  })
}
resource "null_resource" "generate-deployment" {
  triggers = {
    template = local.deployment_content
  }
  provisioner "local-exec" {
    command = format("cat <<\"EOF\" > \"%s\"\n%s\nEOF",
      "deployment.yaml",
    local.deployment_content)
  }
}
###################
# Generate AKS infomation
###################
resource "null_resource" "generate-aks-information" {
  triggers = {
    template = local.deployment_content
  }
  provisioner "local-exec" {
    command = "echo ${module.demo-aks.name} > aks-name"
  }
}