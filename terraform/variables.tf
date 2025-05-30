variable "project_id" {
  description = "The GCP project ID to deploy to."
  type        = string
}

variable "region" {
  description = "The GCP region for resources."
  type        = string
  default     = "us-central1"
}

variable "node_count" {
  description = "Number of nodes in the GKE node pool."
  type        = number
  default     = 2
}

variable "node_machine_type" {
  description = "Machine type for GKE nodes."
  type        = string
  default     = "e2-medium"
}

variable "env" {
  description = "Environment label for resources."
  type        = string
  default     = "dev"
}
