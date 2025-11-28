terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 7.0.0"
    }
  }
}

provider "oci" {
  region              = "us-ashburn-1"
  auth                = "APIKey"
  config_file_profile = "default"
}

variable "compartment_id" {
  type = string
}

variable "vm_count" {
  type    = number
  default = 2
}

variable "vm_names" {
  type    = list(string)
  default = ["vm-1", "vm-2", "vm-3"]
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard2.1"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# VCN
resource "oci_core_vcn" "internal" {
  cidr_block     = "172.16.0.0/20"
  compartment_id = var.compartment_id
  display_name   = "MyVCN"
  dns_label      = "internal"
}

# Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.internal.id
  display_name   = "InternetGateway"
}

# Route Table
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.internal.id
  display_name   = "PublicRouteTable"

  route_rules {
    description       = "Internet Gateway"
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Security list
resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.internal.id
  display_name   = "SSH-Internet"

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

# Public subnet
resource "oci_core_subnet" "public" {
  vcn_id                  = oci_core_vcn.internal.id
  cidr_block              = "172.16.1.0/24"
  compartment_id          = var.compartment_id
  display_name            = "PublicSubnet"
  dns_label               = "public"
  availability_domain     = data.oci_identity_availability_domains.ads.availability_domains[0].name
  prohibit_public_ip_on_vnic = false
  security_list_ids       = [oci_core_security_list.public.id]
  route_table_id          = oci_core_route_table.public_rt.id

  depends_on = [oci_core_internet_gateway.igw]
}

# VMs
resource "oci_core_instance" "vms" {
  for_each = { for i in range(var.vm_count) : i => {
    name = length(var.vm_names) > i ? var.vm_names[i] : "vm-${i + 1}"
  }}

  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard2.1"
  display_name        = each.value.name

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file("~/.ssh/my_oci_key.pub")
  }
}

output "vm_ips" {
  value = { for k, vm in oci_core_instance.vms : vm.display_name => vm.public_ip }
}

output "ssh_commands" {
  value = { for k, vm in oci_core_instance.vms : vm.display_name => "ssh -i ~/.ssh/my_oci_key ubuntu@${vm.public_ip}" }
}
