# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required Google APIs
resource "google_project_service" "container" {
  project = var.project_id
  service = "container.googleapis.com"
  
  # This allows Terraform to disable the service when destroying
  disable_on_destroy = true
  # This allows disabling services that have dependencies
  disable_dependent_services = true
}

resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"
  
  # This allows Terraform to disable the service when destroying
  disable_on_destroy = true
  # This allows disabling services that have dependencies
  disable_dependent_services = true
}

# Enable Service Usage API (often required for managing other APIs)
resource "google_project_service" "serviceusage" {
  project = var.project_id
  service = "serviceusage.googleapis.com"
  
  disable_on_destroy = false  # Usually should not be disabled
}

# Create a custom VPC for GKE
resource "google_compute_network" "genkart_vpc" {
  name                    = "genkart-vpc"
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.compute]
}

# Create a subnet for GKE (primary subnet for pods/services)
resource "google_compute_subnetwork" "genkart_subnet" {
  name          = "genkart-subnet"
  ip_cidr_range = "10.10.0.0/16"
  region        = var.region
  network       = google_compute_network.genkart_vpc.id
  # Enable Private Google Access for GKE nodes
  private_ip_google_access = true

  # Secondary range for pods
  secondary_ip_range {
    range_name    = "genkart-pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  # Secondary range for services
  secondary_ip_range {
    range_name    = "genkart-services"
    ip_cidr_range = "10.30.0.0/20"
  }
  
  depends_on = [google_project_service.compute]
}

# Create a NAT gateway for outbound internet access from private nodes
resource "google_compute_router" "genkart_router" {
  name    = "genkart-router"
  network = google_compute_network.genkart_vpc.id
  region  = var.region
  
  depends_on = [google_project_service.compute]
}

resource "google_compute_router_nat" "genkart_nat" {
  name                                = "genkart-nat"
  router                              = google_compute_router.genkart_router.name
  region                              = var.region
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  enable_endpoint_independent_mapping = true
  
  depends_on = [google_project_service.compute]
}

# Create a GKE cluster with advanced security and networking
resource "google_container_cluster" "genkart_gke" {
  name       = "genkart-gke"
  location   = var.region
  network    = google_compute_network.genkart_vpc.id
  subnetwork = google_compute_subnetwork.genkart_subnet.id

  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "genkart-pods"
    services_secondary_range_name = "genkart-services"
  }

  # Enable shielded nodes for security
  enable_shielded_nodes = true

  # Enable network policy for pod-level security
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Enable master authorized networks (restrict API access)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks (customize for prod)"
    }
  }

  # Disable basic auth and client certificate (recommended by Google)
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Enable HTTP load balancing (GCLB)
  addons_config {
    http_load_balancing {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Enable private nodes (optional, for production)
  # private_cluster_config {
  #   enable_private_nodes    = true
  #   enable_private_endpoint = false
  #   master_ipv4_cidr_block  = "172.16.0.0/28"
  # }
  
  depends_on = [
    google_project_service.container,
    google_project_service.compute
  ]
}

# Create a node pool for the cluster with autoscaling and security
resource "google_container_node_pool" "genkart_nodes" {
  name     = "genkart-node-pool"
  cluster  = google_container_cluster.genkart_gke.name
  location = var.region

  node_count = var.node_count

  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }

  node_config {
    machine_type = var.node_machine_type
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    labels = {
      env = var.env
    }
    tags = ["genkart-node"]
    # Enable shielded VM features
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    # Enable GKE metadata server
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
  
  depends_on = [
    google_project_service.container,
    google_project_service.compute
  ]
}

# Firewall rule for internal communication
resource "google_compute_firewall" "genkart-allow-internal" {
  name    = "genkart-allow-internal"
  network = google_compute_network.genkart_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["10.10.0.0/16", "10.20.0.0/16"]
  
  depends_on = [google_project_service.compute]
}

# Firewall rule for node ports (for debugging/ingress)
resource "google_compute_firewall" "genkart-allow-nodeports" {
  name    = "genkart-allow-nodeports"
  network = google_compute_network.genkart_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["genkart-node"]
  
  depends_on = [google_project_service.compute]
}

# Firewall rule for health checks
resource "google_compute_firewall" "genkart-allow-health-checks" {
  name    = "genkart-allow-health-checks"
  network = google_compute_network.genkart_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  
  depends_on = [google_project_service.compute]
}

# Reserve a static IP for the GKE ingress (for stable DNS and HTTPS)
resource "google_compute_address" "genkart_ingress_ip" {
  name   = "genkart-ingress-ip"
  region = var.region
  
  depends_on = [google_project_service.compute]
}

# Firewall rule for frontend (client) service (port 3000)
resource "google_compute_firewall" "genkart-allow-client" {
  name    = "genkart-allow-client"
  network = google_compute_network.genkart_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["genkart-node"]
  
  depends_on = [google_project_service.compute]
}

# Firewall rule for backend (server) service (port 5555)
resource "google_compute_firewall" "genkart-allow-server" {
  name    = "genkart-allow-server"
  network = google_compute_network.genkart_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["5555"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["genkart-node"]
  
  depends_on = [google_project_service.compute]
}

# Firewall rule for ArgoCD UI (port 8080)
resource "google_compute_firewall" "genkart-allow-argocd" {
  name    = "genkart-allow-argocd"
  network = google_compute_network.genkart_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["genkart-node"]
  
  depends_on = [google_project_service.compute]
}

# Firewall rule for SonarQube (port 9000)
resource "google_compute_firewall" "genkart-allow-sonarqube" {
  name    = "genkart-allow-sonarqube"
  network = google_compute_network.genkart_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["9000"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["genkart-node"]
  
  depends_on = [google_project_service.compute]
}