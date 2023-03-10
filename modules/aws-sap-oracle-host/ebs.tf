/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: MIT-0
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this
 * software and associated documentation files (the "Software"), to deal in the Software
 * without restriction, including without limitation the rights to use, copy, modify,
 * merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
 * PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

locals {
  oracle_data_size         = var.oracle_disks_data_storage_type == "gp2" ? var.oracle_disks_data_gp2[var.instance_type].disk_size : var.oracle_disks_data_storage_type == "io1" ? var.oracle_disks_data_io1[var.instance_type].disk_size : (var.oracle_disks_data_storage_type == "gp3" ? var.oracle_disks_data_gp3[var.instance_type].disk_size : 0)
  oracle_data_disks_number = var.oracle_disks_data_storage_type == "gp2" ? var.oracle_disks_data_gp2[var.instance_type].disk_nb : var.oracle_disks_data_storage_type == "io1" ? var.oracle_disks_data_io1[var.instance_type].disk_nb : (var.oracle_disks_data_storage_type == "gp3" ? var.oracle_disks_data_gp3[var.instance_type].disk_nb : 0)
  oracle_log_size          = var.oracle_disks_logs_storage_type == "gp2" ? var.oracle_disks_logs_gp2[var.instance_type].disk_size : var.oracle_disks_logs_storage_type == "io1" ? var.oracle_disks_logs_io1[var.instance_type].disk_size : (var.oracle_disks_logs_storage_type == "gp3" ? var.oracle_disks_logs_gp3[var.instance_type].disk_size : 0)
  oracle_log_disks_number  = var.oracle_disks_logs_storage_type == "gp2" ? var.oracle_disks_logs_gp2[var.instance_type].disk_nb : var.oracle_disks_logs_storage_type == "io1" ? var.oracle_disks_logs_io1[var.instance_type].disk_nb : (var.oracle_disks_logs_storage_type == "gp3" ? var.oracle_disks_logs_gp3[var.instance_type].disk_nb : 0)
  data_volume_names      = formatlist("%s", null_resource.data_volume_names_list.*.triggers.data_volume_name)
  log_volume_names       = formatlist("%s", null_resource.log_volume_names_list.*.triggers.log_volume_name)
}

resource "null_resource" "data_volume_names_list" {
  count = var.enabled ? local.oracle_data_disks_number : 0

  triggers = {
    data_volume_name = count.index == 0 ? "/dev/xvdf" : count.index == 1 ? "/dev/xvdg" : count.index == 2 ? "/dev/xvdh" : count.index == 3 ? "/dev/xvdi" : count.index == 4 ? "/dev/xvdj" : count.index == 5 ? "/dev/xvdk" : count.index == 6 ? "/dev/xvdl" : ""
  }
}

resource "null_resource" "log_volume_names_list" {
  count = var.enabled ? local.oracle_log_disks_number : 0

  triggers = {
    log_volume_name = count.index == 0 ? "/dev/xvdm" : count.index == 1 ? "/dev/xvdn" : count.index == 2 ? "/dev/xvdo" : count.index == 3 ? "/dev/xvdp" : count.index == 4 ? "/dev/xvdq" : ""
  }
}

# Oracle Disks volume (/dev/oracle)
resource "aws_ebs_volume" "xvdr_volume" {
  availability_zone = element(module.instance.availability_zone, count.index)
  size              = var.oracle_disks_shared_size
  type              = var.oracle_disks_shared_storage_type
  kms_key_id        = var.kms_key_arn
  encrypted         = var.kms_key_arn != "" ? true : false
  lifecycle {
    ignore_changes = [kms_key_id, encrypted]
  }
  count = var.enabled ? 1 : 0
  tags = merge(
    module.tags.values,
  tomap({ "Name" = "${module.tags.values["Name"]}-oracle_shared" }))
}

resource "aws_volume_attachment" "ebs_attach_xvdr" {
  device_name = "/dev/xvdr"
  count       = var.enabled ? 1 : 0
  volume_id   = aws_ebs_volume.xvdr_volume.*.id[count.index]
  instance_id = module.instance.instance_id[count.index]
}

# oracle Disks for DATA volumes
resource "aws_ebs_volume" "data_volumes" {
  availability_zone = element(module.instance.availability_zone, floor(count.index / local.oracle_data_disks_number))
  size              = local.oracle_data_size
  type              = var.oracle_disks_data_storage_type
  encrypted         = var.kms_key_arn != "" ? true : false
  kms_key_id        = var.kms_key_arn
  lifecycle {
    ignore_changes = [kms_key_id, encrypted]
  }
  count = var.enabled ? var.instance_count * local.oracle_data_disks_number : 0
  tags = merge(
    module.tags.values,
  tomap({ "Name" = "${module.tags.values["Name"]}-oracle_data-${count.index}" }))
}

resource "aws_volume_attachment" "ebs_attach_data_volumes" {
  device_name = local.data_volume_names[count.index % local.oracle_data_disks_number]
  count       = var.enabled ? var.instance_count * local.oracle_data_disks_number : 0
  volume_id   = aws_ebs_volume.data_volumes.*.id[count.index]
  instance_id = module.instance.instance_id[floor(count.index / local.oracle_data_disks_number)]
}


# oracle Disks for LOG volumes
resource "aws_ebs_volume" "log_volumes" {
  availability_zone = element(module.instance.availability_zone, floor(count.index / local.oracle_log_disks_number))
  size              = local.oracle_log_size
  type              = var.oracle_disks_logs_storage_type
  encrypted         = var.kms_key_arn != "" ? true : false
  kms_key_id        = var.kms_key_arn
  lifecycle {
    ignore_changes = [kms_key_id, encrypted]
  }
  count = var.enabled ? var.instance_count * local.oracle_log_disks_number : 0
  tags = merge(
    module.tags.values,
  tomap({ "Name" = "${module.tags.values["Name"]}-oracle_log-${count.index}" }))
}

resource "aws_volume_attachment" "ebs_attach_log_volumes" {
  device_name = local.log_volume_names[count.index % local.oracle_log_disks_number]
  count       = var.enabled ? var.instance_count * local.oracle_log_disks_number : 0
  volume_id   = aws_ebs_volume.log_volumes.*.id[count.index]
  instance_id = module.instance.instance_id[floor(count.index / local.oracle_log_disks_number)]

}

# Hana Disk for BACKUP volume (/dev/xvds)
resource "aws_ebs_volume" "backup_volumes" {
  availability_zone = element(module.instance.availability_zone, count.index)
  # Assumption that locally we will retain 1 backup on the local EBS Volume
  size       = var.oracle_disks_usr_sap_storage_size
  type       = var.oracle_disks_backup_storage_type
  kms_key_id = var.kms_key_arn
  encrypted  = var.kms_key_arn != "" ? true : false
 lifecycle {
    ignore_changes = [kms_key_id, encrypted]
  }
  count = var.enabled ? 1 : 0
  tags = merge(
    module.tags.values,
  tomap({ "Name" = "${module.tags.values["Name"]}-oracle_backup" }))
}

resource "aws_volume_attachment" "ebs_attach_backup_volumes" {
  device_name = "/dev/xvds"
  count       = var.enabled ? 1 : 0
  volume_id   = aws_ebs_volume.backup_volumes.*.id[count.index]
  instance_id = module.instance.instance_id[count.index]
}

# oracle Disk for USR/SAP volume (/dev/xvdt)
resource "aws_ebs_volume" "usr_sap_volumes" {
  availability_zone = element(module.instance.availability_zone, count.index)
  size              = var.oracle_disks_usr_sap_storage_size
  type              = var.oracle_disks_usr_sap_storage_type
  kms_key_id        = var.kms_key_arn
  encrypted         = var.kms_key_arn != "" ? true : false
  lifecycle {
    ignore_changes = [kms_key_id, encrypted]
  }
  count = var.enabled ? var.instance_count : 0
  tags = merge(
    module.tags.values,
  tomap({ "Name" = "${module.tags.values["Name"]}-oracle_usr_sap" }))
}

resource "aws_volume_attachment" "ebs_attach_xvdt" {
  device_name = "/dev/xvdt"
  count       = var.enabled ? var.instance_count : 0
  volume_id   = aws_ebs_volume.usr_sap_volumes.*.id[count.index]
  instance_id = module.instance.instance_id[count.index]
}

# oracle Disk for SWAP volume (/dev/xvdu)
resource "aws_ebs_volume" "xvdu_volume" {
  availability_zone = element(module.instance.availability_zone, count.index)
  size              = 50
  type              = "gp3"
  kms_key_id        = var.kms_key_arn
  encrypted         = var.kms_key_arn != "" ? true : false
  lifecycle {
    ignore_changes = [kms_key_id, encrypted]
  }
  count = var.enabled ? var.instance_count : 0

  tags = merge(
    module.tags.values,
  tomap({ "Name" = "${module.tags.values["Name"]}-app_swap" }))
}

resource "aws_volume_attachment" "ebs_attach_xvdu" {
  device_name = "/dev/xvdu"
  count       = var.enabled ? var.instance_count : 0
  volume_id   = aws_ebs_volume.xvdu_volume.*.id[count.index]
  instance_id = module.instance.instance_id[count.index]
}
