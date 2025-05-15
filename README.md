## Prerequisites

# Azure VPN Infrastructure Overview

This Terraform-based Azure infrastructure sets up a VPN-enabled virtual network, virtual machines,
and a site-to-site connection with an on-premises (DigitalOcean) environment.

## Overview of Resources

The configuration provisions the following:

- One resource group
- One virtual network with two subnets
- One Ubuntu VM
- One Key Vault for root certificate management
- One VPN Gateway with a public IP
- One Local Network Gateway (representing DigitalOcean)
- One IPsec VPN connection to DigitalOcean
- Role-based access to Key Vault

## Network Configuration

### Virtual Network (VNet)

- Name: vnet-d01
- Address Space: 10.10.0.0/24

### Subnets

1. **VM Subnet**
    - Name: snet-vm-d01
    - CIDR: 10.10.0.0/26

2. **Gateway Subnet**
    - Name: GatewaySubnet
    - CIDR: 10.10.0.64/26

### VPN Client Address Pool

- CIDR: 172.17.0.0/24

## Virtual Machine

- Name: vm1-d01
- Size: Standard_B2ms
- Username: razumovsky_r
- SSH Public Key Authentication via `${path.root}/id_rsa.pub`
- Public IP attached: pip-vm1-d01
- Network Interface: nic-vm1-d01
- OS Disk Name: osdisk-vm1-d01
- Located in: snet-vm-d01

## Key Vault

- Name: kv-vpn-d01
- SKU: Standard
- Soft Delete: Enabled (7 days)
- RBAC Authorization: Enabled
- Purge Protection: Disabled
- Root Certificate Secret:
    - Name: VpnGateway-RootCert
    - Path: ${path.root}/VpnGateway-RootCert.crt (base64 encoded)

### Role Assignments for Key Vault

- CLI User (current Terraform identity)
- Azure Portal user with ID: 89ab0b10-1214-4c8f-878c-18c3544bb547

## VPN Gateway

- Name: vpn-gw-d01
- Type: RouteBased
- SKU: VpnGw2AZ
- Active/Active: Disabled
- BGP: Disabled
- Public IP: pip-vpn-gw-d01
- Located in: GatewaySubnet (10.10.0.64/26)
- Zones: 1, 2, 3
- VPN Client Configuration:
    - Address Pool: 172.17.0.0/24
    - Root Certificate:
        - Name: VPNROOT
        - Pulled from Key Vault secret: VpnGateway-RootCert

## Local Network Gateway (DigitalOcean)

- Name: lgwy-do-d01
- Public IP: 64.226.118.158
- On-Prem Network Address Space: 10.114.0.0/20

## VPN Connection

- Name: onpremise
- Type: IPsec
- Shared Key: 4-v3ry-53cr37-1p53c-5h4r3d-k3y
- Connects:
    - Azure Virtual Network Gateway: vpn-gw-d01
    - Local Network Gateway: lgwy-do-d01


## Modules

- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_gateway
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/local_network_gateway
