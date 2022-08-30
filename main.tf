/*
 * Copyright 2017 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "template_file" "nat-startup-script" {
  template = file(format("%s/config/startup.sh", path.module))

  vars = {
    squid_enabled = var.squid_enabled
    squid_config  = var.squid_config
    module_path   = path.module
  }
}

data "google_compute_network" "network" {
  name    = var.network
  project = var.network_project == "" ? var.project : var.network_project
}

data "google_compute_address" "default" {
  count   = var.ip_address_name == "" ? 0 : 1
  name    = var.ip_address_name
  project = var.network_project == "" ? var.project : var.network_project
  region  = var.region
}

locals {
  zone          = var.zone == "" ? lookup(var.region_params[var.region], "zone") : var.zone
  name          = "${var.name}nat-gateway-${local.zone}"
  instance_tags = ["${var.tag_preffix}-inst-${local.zonal_tag}", "${var.tag_preffix}-inst-${local.regional_tag}"]
  zonal_tag     = "${var.name}nat-${local.zone}"
  regional_tag  = "${var.name}nat-${var.region}"
}

module "instance_template" {
  source                = "git@github.com:terraform-google-modules/terraform-google-vm.git//modules/instance_template?ref=v7.8.0"

  project_id            = var.project
  subnetwork            = var.subnetwork
  subnetwork_project    = var.network_project == "" ? var.project : var.network_project
  region                = var.region
  service_account       = { email = var.service_account_email, scopes = []}
  name_prefix           = local.name
  tags                  = local.instance_tags
  labels                = var.instance_labels
  can_ip_forward        = "true"
  machine_type          = var.machine_type
  metadata              = var.metadata
  startup_script        = data.template_file.nat-startup-script.rendered
  source_image          = var.compute_image
  network_ip            = var.ip
  disk_size_gb          = 10
  # access_config         = [
  #   {
  #     nat_ip = element(concat(google_compute_address.default.*.address, data.google_compute_address.default.*.address, list("")), 0)
  #   },
  # ]
}

module "nat_gateway_mig" {
  source                    = "git@github.com:terraform-google-modules/terraform-google-vm.git//modules/mig?ref=v7.8.0"

  project_id                = var.project
  region                    = var.region
  subnetwork                = var.subnetwork
  subnetwork_project        = var.network_project == "" ? var.project : var.network_project
  distribution_policy_zones = [local.zone]
  autoscaling_enabled       = false
  wait_for_instances        = true
  hostname                  = local.name
  instance_template         = module.instance_template.self_link
  target_size               = 1
  update_policy             = [
    {
      type                  = "PROACTIVE"
      minimal_action        = "REPLACE"
      max_surge_fixed       = 0
      max_unavailable_fixed = 1
      min_ready_sec         = 30
      instance_redistribution_type = "PROACTIVE"
      max_surge_percent = null
      max_unavailable_percent = null
      replacement_method = "RECREATE"
    },
  ]
}

# module "nat-gateway_dep" {
#   source                = "git@github.com:stone-payments/terraform-google-managed-instance-group.git?ref=terraform13support"
#   module_enabled        = var.module_enabled
#   project               = var.project
#   region                = var.region
#   name                  = local.name
#   network               = var.network
#   subnetwork            = var.subnetwork
#   subnetwork_project    = var.network_project == "" ? var.project : var.network_project

#   # zone                  = local.zone  
#   # wait_for_instances    = true
#   # service_port          = "80"
#   # service_port_name     = "http"
#   # http_health_check     = var.autohealing_enabled
#   # size                  = 1
#   # network_ip            = var.ip
#   # update_strategy = "ROLLING_UPDATE"
#   # rolling_update_policy = [
#   #   {
#   #     type                  = "PROACTIVE"
#   #     minimal_action        = "REPLACE"
#   #     max_surge_fixed       = 0
#   #     max_unavailable_fixed = 1
#   #     min_ready_sec         = 30
#   #   },
#   # ]

#   ssh_fw_rule           = var.ssh_fw_rule
#   ssh_source_ranges     = var.ssh_source_ranges

#   # compute_image         = var.compute_image
#   # startup_script        = data.template_file.nat-startup-script.rendered
#   # metadata              = var.metadata
#   # machine_type          = var.machine_type
#   # can_ip_forward        = "true"
#   # service_account_email = var.service_account_email
#   # target_tags           = local.instance_tags
#   # instance_labels       = var.instance_labels
#   # access_config = [
#   #   {
#   #     nat_ip = element(concat(google_compute_address.default.*.address, data.google_compute_address.default.*.address, list("")), 0)
#   #   },
#   # ]
# }

# resource "google_compute_address" "default" {
#   count   = var.module_enabled && var.ip_address_name == "" ? 1 : 0
#   name    = local.zonal_tag
#   project = var.project
#   region  = var.region
# }
