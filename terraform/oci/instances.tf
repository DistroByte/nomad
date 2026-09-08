resource "oci_core_instance" "observability" {
  compartment_id      = var.compartment_ocid
  availability_domain = "IwkV:UK-LONDON-1-AD-3"
  fault_domain        = "FAULT-DOMAIN-1"
  display_name        = "observability"
  shape               = "VM.Standard.E2.1.Micro"
  extended_metadata   = {}
  freeform_tags       = {}
  security_attributes = {}

  metadata = {
    "ssh_authorized_keys" = <<-EOT
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIDg4A77LUlRC9xiijAdNWgZFElCXkyickyh6g/FpltK
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPm0mpiljISe3WL72k7kBHRNuEq5LvG3jL51y0Opy+lc
    EOT
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Java Management Service"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Autonomous Linux"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Service Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Hub Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Run Command"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }

  availability_config {
    is_live_migration_preferred = false
    recovery_action             = "RESTORE_INSTANCE"
  }

  create_vnic_details {
    assign_ipv6ip             = false
    assign_private_dns_record = false
    assign_public_ip          = "true"
    display_name              = "instance-20240823-1301"
    hostname_label            = "instance-20240823-1301"
    freeform_tags             = {}
    nsg_ids                   = []
    private_ip                = "10.0.0.59"
    security_attributes       = {}
    skip_source_dest_check    = false
    subnet_id                 = oci_core_subnet.homelab.id
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = false
  }

  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    is_consistent_volume_naming_enabled = true
    is_pv_encryption_in_transit_enabled = false
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
  }

  shape_config {
    ocpus = 1
  }

  source_details {
    source_type                     = "image"
    source_id                       = "ocid1.image.oc1.uk-london-1.aaaaaaaalmz2f3ryfakc4fd5r4uteua3az3dfvcxr6q77b2nvddzevscjk5q"
    boot_volume_size_in_gbs         = "47"
    boot_volume_vpus_per_gb         = "10"
    is_preserve_boot_volume_enabled = false
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [metadata]
  }
}

resource "oci_core_instance" "worker" {
  compartment_id      = var.compartment_ocid
  availability_domain = "IwkV:UK-LONDON-1-AD-3"
  fault_domain        = "FAULT-DOMAIN-1"
  display_name        = "worker"
  shape               = "VM.Standard.E2.1.Micro"
  extended_metadata   = {}
  freeform_tags       = {}
  security_attributes = {}

  metadata = {
    "ssh_authorized_keys" = <<-EOT
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIDg4A77LUlRC9xiijAdNWgZFElCXkyickyh6g/FpltK
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPm0mpiljISe3WL72k7kBHRNuEq5LvG3jL51y0Opy+lc
    EOT
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Java Management Service"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Autonomous Linux"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Service Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Hub Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Run Command"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }

  availability_config {
    is_live_migration_preferred = false
    recovery_action             = "RESTORE_INSTANCE"
  }

  create_vnic_details {
    assign_ipv6ip             = false
    assign_private_dns_record = false
    assign_public_ip          = "true"
    display_name              = "instance-20240819-1830"
    hostname_label            = "instance-20240819-1830"
    freeform_tags             = {}
    nsg_ids                   = []
    private_ip                = "10.0.0.97"
    security_attributes       = {}
    skip_source_dest_check    = false
    subnet_id                 = oci_core_subnet.homelab.id
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = false
  }

  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    is_consistent_volume_naming_enabled = true
    is_pv_encryption_in_transit_enabled = false
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
  }

  shape_config {
    ocpus = 1
  }

  source_details {
    source_type                     = "image"
    source_id                       = "ocid1.image.oc1.uk-london-1.aaaaaaaalmz2f3ryfakc4fd5r4uteua3az3dfvcxr6q77b2nvddzevscjk5q"
    boot_volume_size_in_gbs         = "47"
    boot_volume_vpus_per_gb         = "10"
    is_preserve_boot_volume_enabled = false
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [metadata]
  }
}
