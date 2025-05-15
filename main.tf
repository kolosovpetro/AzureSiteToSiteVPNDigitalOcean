data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

#################################################################################################################
# LOCALS
#################################################################################################################

locals {
  vnet_cidr           = ["10.10.0.0/24"]
  vm_subnet_cidr      = ["10.10.0.0/26"]
  gateway_subnet_cidr = ["10.10.0.64/26"]
}

#################################################################################################################
# RESOURCE GROUP
#################################################################################################################

resource "azurerm_resource_group" "public" {
  location = var.location
  name     = "rg-s2s-connection-${var.prefix}"
  tags     = var.tags
}

#################################################################################################################
# VNET AND SUBNET
#################################################################################################################

resource "azurerm_virtual_network" "public" {
  name                = "vnet-${var.prefix}"
  address_space       = local.vnet_cidr
  location            = azurerm_resource_group.public.location
  resource_group_name = azurerm_resource_group.public.name
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm-${var.prefix}"
  resource_group_name  = azurerm_resource_group.public.name
  virtual_network_name = azurerm_virtual_network.public.name
  address_prefixes     = local.vm_subnet_cidr
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.public.name
  virtual_network_name = azurerm_virtual_network.public.name
  address_prefixes     = local.gateway_subnet_cidr
}

##########################################################################
# VIRTUAL MACHINES
##########################################################################

module "vm1" {
  source                      = "github.com/kolosovpetro/AzureLinuxVMTerraform.git//modules/ubuntu-vm-key-auth?ref=master"
  resource_group_name         = azurerm_resource_group.public.name
  resource_group_location     = azurerm_resource_group.public.location
  subnet_id                   = azurerm_subnet.vm.id
  ip_configuration_name       = "ipc-vm1-${var.prefix}"
  network_interface_name      = "nic-vm1-${var.prefix}"
  os_profile_computer_name    = "vm1-${var.prefix}"
  storage_os_disk_name        = "osdisk-vm1-${var.prefix}"
  vm_name                     = "vm1-${var.prefix}"
  os_profile_admin_public_key = file("${path.root}/id_rsa.pub")
  os_profile_admin_username   = "razumovsky_r"
  network_security_group_id   = azurerm_network_security_group.public.id
  vm_size                     = "Standard_B2ms"
  public_ip_name              = "pip-vm1-${var.prefix}"
}

##########################################################################
# KEYVAULT
##########################################################################

resource "azurerm_key_vault" "public" {
  name                        = "kv-vpn-${var.prefix}"
  location                    = azurerm_resource_group.public.location
  resource_group_name         = azurerm_resource_group.public.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  enable_rbac_authorization   = true
  sku_name                    = "standard"
}

##########################################################################
# RBAC
##########################################################################

resource "azurerm_role_assignment" "cli_rbac" {
  scope                = azurerm_key_vault.public.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "azure_portal_rbac" {
  scope                = azurerm_key_vault.public.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = "89ab0b10-1214-4c8f-878c-18c3544bb547"
}

##########################################################################
# SECRETS
##########################################################################

resource "azurerm_key_vault_secret" "root_certificate" {
  name         = "VpnGateway-RootCert"
  value        = filebase64("${path.root}/VpnGateway-RootCert.crt")
  key_vault_id = azurerm_key_vault.public.id

  depends_on = [
    azurerm_role_assignment.cli_rbac
  ]
}

data "azurerm_key_vault_secret" "root_certificate" {
  name         = "VpnGateway-RootCert"
  key_vault_id = azurerm_key_vault.public.id

  depends_on = [
    azurerm_key_vault_secret.root_certificate
  ]
}


##########################################################################
# VPN GATEWAY PUBLIC IP
##########################################################################

resource "azurerm_public_ip" "vpn_gw_pip" {
  name                = "pip-vpn-gw-${var.prefix}"
  location            = azurerm_resource_group.public.location
  resource_group_name = azurerm_resource_group.public.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

##########################################################################
# VPN GATEWAY
##########################################################################

resource "azurerm_virtual_network_gateway" "public" {
  name                = "vpn-gw-${var.prefix}"
  location            = azurerm_resource_group.public.location
  resource_group_name = azurerm_resource_group.public.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  enable_bgp          = false
  sku                 = "VpnGw2AZ"

  ip_configuration {
    name                          = "ipc-vpn-gw-${var.prefix}"
    public_ip_address_id          = azurerm_public_ip.vpn_gw_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  vpn_client_configuration {
    address_space = ["172.17.0.0/24"]

    root_certificate {
      name             = "VPNROOT"
      public_cert_data = data.azurerm_key_vault_secret.root_certificate.value
    }
  }
}

##########################################################################
# LOCAL NETWORK GATEWAY
##########################################################################

resource "azurerm_local_network_gateway" "do" {
  name                = "lgwy-do-${var.prefix}"
  resource_group_name = azurerm_resource_group.public.name
  location            = azurerm_resource_group.public.location
  gateway_address     = "64.226.118.158"   # public ip address DO droplet
  address_space       = ["10.114.0.0/20"] # address range of the DO network
}

##########################################################################
# VIRTUAL NETWORK GATEWAY CONNECTION
##########################################################################

resource "azurerm_virtual_network_gateway_connection" "do" {
  name                = "vcn-do-${var.prefix}"
  location            = azurerm_resource_group.public.location
  resource_group_name = azurerm_resource_group.public.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.public.id
  local_network_gateway_id   = azurerm_local_network_gateway.do.id

  shared_key = "4-v3ry-53cr37-1p53c-5h4r3d-k3y"
}
