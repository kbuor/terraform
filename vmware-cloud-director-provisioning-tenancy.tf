## DECLARE VARIABLE

variable "vcd_provider_password"  { default = "" }       # Password for Terraform Account

variable "org_name"               { default = "ORG-XXX" }            # Name for Organization
variable "orgvdc_name"            { default = "ORGVDC-XXX" }         # Name for Organization Virtual Datacenter
variable "org_full_name"          { default = "" }                   # Description for Organization and Organization Virtual Datacenter
variable "edgegateway_name"       { default = "EDGE-XXX-01" }        # Name for Edge Gateway


variable "org_user_name"          { default = "XXX_admin" }          # Name for Organization user
variable "org_user_password"      { default = "change-me" }          # Password for Organization user
variable "org_user_description"   { default = ""}                    # Description for Organization user


variable "cpu_allocated"          { default = "" } # vCPU in MHz              # Allocation of vCPU in MHz
variable "memory_allocated"       { default = "" } # Memory in GB             # Allocation of RAM in GB 
variable "storage_allocated"      { default = "" } # Storage in GB            # Allocation of Storage in GB 


variable "edgegateway_primaryip"    { default = ""}       # Primary Public IP for Edge Gateway
variable "edgegateway_startip"      { default = ""}       # Additional Public IP for Edge Gateway
variable "edgegateway_endip"        { default = ""}       # Additional Public IP for Edge Gateway


#=================================================================================#
## !!!!! SYSTEM VARIABLE - DO NOT EDIT !!!!!!                                     #
## CONTACT MR. LUAN OR MR. KBUOR FOR MORE DETAIL                                  #
#---------------------------------------------------------------------------------#
variable "vcd_provider_user"      { default = "terraform" }                       #
variable "vcd_provider_password"  { default = "anLOtJDEf2esMPYd3gI9M3Fm" }        #
variable "vcd_url"                { default = "https://console.tpcloud.vn/api" }  #
variable "org_user_role"          { default = "Organization Administrator"}       #
variable "provider_vdc_name"      { default = "TPCOMS-PROVIDER-VDC-01"}           #
variable "allocation_model"       { default = "AllocationPool"}                   #
variable "network_pool_name"      { default = "TPCOMS-NETWORK-POOL-01"}           #
variable "external_network_name"  { default = "TPCOMS-PROVIDER-GATEWAY-01" }      #
variable "network_quota"          { default = "100" }                             #
variable "cpu_speed"              { default = "1000" }                            #
variable "cpu_guaranteed"         { default = "0.05" }                            #
variable "memory_guaranteed"      { default = "0.05" }                            #
variable "edge_cluster_id"        { default = "edge-provider-01-cluster" }        #
variable "storage_name"           { default = "vSAN Enterprise Plus" }            #
variable "edgegateway_gateway"    { default = "103.141.177.1"}                    #
variable "edgegateway_prefix"     { default = "24"}                               #
#=================================================================================#

## INITIAL VMWARE CLOUD DIRECTOR PLUGIN WITH TERRAFORM
terraform {
  required_providers {
    vcd = {
      source  = "vmware/vcd"
      version = "~> 3.0"
    }
  }
}

## CONNECT TO VMWARE CLOUD DIRECTOR PROVIDER
provider "vcd" {
  user                 = var.vcd_provider_user
  password             = var.vcd_provider_password
  org                  = "system"
  url                  = var.vcd_url
  allow_unverified_ssl = true
}

## CREATE ORGANIZATION (ORG)
resource "vcd_org" "tenant" {
  name                        = var.org_name
  full_name                   = var.org_full_name
  is_enabled                  = true
  delete_recursive            = true
  can_publish_catalogs        = true
  can_publish_external_catalogs = true
  stored_vm_quota             = 0
  deployed_vm_quota           = 0
  vapp_lease {
    maximum_runtime_lease_in_sec          = 0
    power_off_on_runtime_lease_expiration = true
    maximum_storage_lease_in_sec          = 0
    delete_on_storage_lease_expiration    = false
  }
  vapp_template_lease {
    maximum_storage_lease_in_sec       = 0
    delete_on_storage_lease_expiration = true
  }
}

## CREATE ORGANIZATION USER
resource "vcd_org_user" "org_user" {
  org = var.org_name

  name        = var.org_user_name
  description = var.org_user_description
  role        = var.org_user_role
  password    = var.org_user_password

  depends_on  = [vcd_org.tenant]
}

## CREATE ORGANIZATION VIRTUAL DATACENTER (ORGVDC)
resource "vcd_org_vdc" "vdc" {
  name        = var.orgvdc_name
  description = var.org_full_name
  org         = var.org_name

  allocation_model  = var.allocation_model
  network_pool_name = var.network_pool_name
  provider_vdc_name = var.provider_vdc_name
  network_quota     = var.network_quota
  cpu_speed         = var.cpu_speed
  cpu_guaranteed    = var.cpu_guaranteed
  memory_guaranteed = var.memory_guaranteed

  compute_capacity {
    cpu {
      allocated = var.cpu_allocated
    }

    memory {
      allocated = var.memory_allocated
    }
  }

  storage_profile {
    name    = var.storage_name
    limit   = var.storage_allocated
    default = true
  }

  enabled                  = true
  enable_thin_provisioning = true
  enable_fast_provisioning = true
  delete_force             = true
  delete_recursive         = true

  depends_on = [vcd_org.tenant]
}

## CREATE NSX-T EDGE GATEWAY

data "vcd_external_network_v2" "nsxt-ext-net" {
  name = var.external_network_name
}

resource "vcd_nsxt_edgegateway" "nsxt-edge" {
  org         = var.org_name
  name        = var.edgegateway_name
  owner_id    = vcd_org_vdc.vdc.id
  description = "NSX-T Edge Gateway for organization"

  external_network_id = data.vcd_external_network_v2.nsxt-ext-net.id

  subnet {
    gateway       = var.edgegateway_gateway
    prefix_length = var.edgegateway_prefix
    primary_ip = var.edgegateway_primaryip
    allocated_ips {
      start_address = var.edgegateway_startip
      end_address   = var.edgegateway_endip
    }
  }
  depends_on = [vcd_org.tenant, vcd_org_vdc.vdc]
}

## CREATE ROUTED NETWORK
resource "vcd_network_routed_v2" "nsxt-backed" {
  org         = var.org_name
  name        = "Default_Network"
  description = "Default routed Org VDC network backed by NSX-T"

  edge_gateway_id = vcd_nsxt_edgegateway.nsxt-edge.id

  gateway            = "172.168.192.1"
  prefix_length      = 24
  guest_vlan_allowed = false

  static_ip_pool {
    start_address = "172.168.192.51"
    end_address   = "172.168.192.99"
  }

  depends_on = [vcd_nsxt_edgegateway.nsxt-edge]
}
resource "vcd_nsxt_network_dhcp" "pools" {
  org_network_id = vcd_network_routed_v2.nsxt-backed.id
  org         = var.org_name
  dns_servers = ["8.8.8.8", "1.1.1.1"]

  pool {
    start_address = "172.168.192.101"
    end_address   = "172.168.192.199"
  }
  depends_on = [vcd_network_routed_v2.nsxt-backed]
}
resource "vcd_nsxt_nat_rule" "snat" {
  org         = var.org_name

  edge_gateway_id = vcd_nsxt_edgegateway.nsxt-edge.id

  name        = "SNAT_172.168.192.0/24"
  rule_type   = "SNAT"
  description = "Default SNAT"

  # Using primary_ip from edge gateway
  external_address         = var.edgegateway_primaryip
  internal_address         = "172.168.192.0/24"
  logging                  = true
}

## CREATE FIREWALL RULE
resource "vcd_nsxt_firewall" "firewall" {
  org         = var.org_name

  edge_gateway_id = vcd_nsxt_edgegateway.nsxt-edge.id

  rule {
    action      = "ALLOW"
    name        = "allow all IPv4 traffic"
    direction   = "IN_OUT"
    ip_protocol = "IPV4"
  }
  depends_on = [vcd_network_routed_v2.nsxt-backed]
}
