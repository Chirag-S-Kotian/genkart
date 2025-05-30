# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Create a custom VPC for GKE
resource "google_compute_network" "genkart_vpc" {
  name = "genkart-vpc"
  auto_create_subnetworks = false
}

# Create a subnet for GKE
resource "google_compute_subnetwork" "genkart_subnet" {
  name          = "genkart-subnet"
  ip_cidr_range = "10.10.0.0/16"
  region        = var.region
  network       = google_compute_network.genkart_vpc.id
}

# Create a GKE cluster
resource "google_container_cluster" "genkart_gke" {
  name     = "genkart-gke"
  location = var.region
  network    = google_compute_network.genkart_vpc.id
  subnetwork = google_compute_subnetwork.genkart_subnet.id

  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {}

  # Disable basic auth and client certificate (recommended by Google)
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

# Create a node pool for the cluster
resource "google_container_node_pool" "genkart_nodes" {
  name       = "genkart-node-pool"
  cluster    = google_container_cluster.genkart_gke.name
  location   = var.region

  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    labels = {
      env = var.env
    }
    tags = ["genkart-node"]
  }
}

# Output kubeconfig
output "kubeconfig" {
  value = google_container_cluster.genkart_gke.endpoint
  description = "GKE cluster endpoint. Use 'gcloud container clusters get-credentials' to configure kubectl."
}
