variable "gcp_project" {
  type        = string
  description = "GCP Project ID"
  default     = "sigma-smile-251818"
}

variable "gcp_region" {
  type        = string
  description = "GCP region for deployment"
  default     = "us-east1"
}

variable "gcp_zone" {
  type        = string
  description = "GCP zone for deployment"
  default     = "us-east1-b"
}

variable "instance_image" {
  type        = string
  description = "Base image for GCP VM"
  default     = "debian-cloud/debian-11"
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames in VPC"
  default     = true
}

variable "dns_managed_zone" {
  type        = string
  description = "GCP DNS Zone Name"
  default     = "gcp-public"
}

variable "vpc_cidr_block" {
  type        = string
  description = "Base CIDR Block for VPC"
  default     = "10.0.0.0/16"
}

variable "vpc_public_subnet1_cidr_block" {
  type        = string
  description = "CIDR Block for Subnet 1 in VPC"
  default     = "10.0.0.0/24"
}

variable "map_public_ip_on_launch" {
  type        = bool
  description = "Map a public IP address for Subnet instances"
  default     = true
}

variable "instance_type" {
  type        = string
  description = "Type for Micro Spot Instance"
  default     = "e2-micro"
}

variable "company" {
  type        = string
  description = "Company name for resource tagging"
  default     = "Taco Team"
}

output "URL" {
  value = google_dns_record_set.app-lb.name
}

output "Load-Balancer-IP" {
  value = google_compute_global_address.app.address
}