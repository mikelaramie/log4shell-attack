// Networks 
resource "google_compute_network" "log4shell-project-default-network" {
  project                 = module.log4shell-project.project_id
  name                    = "default"
  auto_create_subnetworks = true
  routing_mode            = "GLOBAL"
}

resource "google_compute_network" "log4shell-project-attack-network" {
  project                 = module.log4shell-project.project_id
  name                    = "attack"
  auto_create_subnetworks = true
  routing_mode            = "GLOBAL"
}

// Firewalls
resource "google_compute_firewall" "default" {
  project = module.log4shell-project.project_id
  name    = "test-firewall"  //TODO: Change Name
  network = google_compute_network.log4shell-project-attack-network.name
  allow {
    protocol = "tcp"
    ports    = ["1389", "22"] //TODO: Add 1099, 8180
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["attack"]
}


// GKE Clusters - cluster-01
// TODO:  Refactor into a module
resource "google_service_account" "log4shell-project-gke-cluster-01" {
  project      = module.log4shell-project.project_id
  account_id   = "gke-cluster-01"
  display_name = "GKE Cluster 01"
}

resource "google_container_cluster" "log4shell-project-cluster-01" {
  project                  = module.log4shell-project.project_id
  name                     = "cluster-01" //TODO - add suffix
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 2
  networking_mode          = "VPC_NATIVE"
  network                  = google_compute_network.log4shell-project-default-network.name
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "" //defaults to /14
    services_ipv4_cidr_block = "" //defaults to /14
  }
}

resource "google_container_node_pool" "log4shell-project-cluster-01-pool-01" {
  project            = module.log4shell-project.project_id
  name               = "pool-01"
  location           = var.zone
  cluster            = google_container_cluster.log4shell-project-cluster-01.name
  initial_node_count = 2

  autoscaling {
    min_node_count = 2
    max_node_count = 5
  }

  node_config {
    preemptible  = true //set to false if you want stable hosts
    machine_type = "e2-standard-4"
    /*
    "e2-standard-4" allows for a suitable number of CPUs to run both the LW agent and
    the Bank of Anthos demo environment.  For a full list of available machine types
    visit https://cloud.google.com/compute/docs/machine-types    
    */
    image_type = "cos"
    /* Available Linux options are "cos", "cos_containerd", "ubuntu", "ubuntu_containerd" 
    For more info (including Windows options) visit
    https://cloud.google.com/kubernetes-engine/docs/concepts/node-images
    */
    service_account = google_service_account.log4shell-project-gke-cluster-01.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

// GCE - Deploy attack instance
resource "google_service_account" "log4shell-project-attack-instance" {
  project      = module.log4shell-project.project_id
  account_id   = "attack-instance"
  display_name = "Attack Instance"
}

resource "google_compute_instance" "log4shell-project-attack-instance" {
  project      = module.log4shell-project.project_id
  name         = "attack-instance"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["attack"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network = google_compute_network.log4shell-project-attack-network.name

    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = "echo hi > /test.txt"

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.log4shell-project-attack-instance.email
    scopes = ["cloud-platform"]
  }
}

data "google_compute_instance" "attack-instance" {
  project = module.log4shell-project.project_id
  zone    = var.zone
  name    = google_compute_instance.log4shell-project-attack-instance.name
}

// K8s - authenticate and deploy Lacework
data "google_client_config" "provider" {}

data "google_container_cluster" "log4shell-project-cluster-01" {
  name     = google_container_cluster.log4shell-project-cluster-01.name
  location = var.zone
  project  = module.log4shell-project.project_id
}

provider "kubernetes" {
  alias = "k8s-log4shell-project-cluster-01"
  host  = "https://${data.google_container_cluster.log4shell-project-cluster-01.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.log4shell-project-cluster-01.master_auth[0].cluster_ca_certificate,
  )
}

resource "kubernetes_namespace" "lacework" {
  provider = kubernetes.k8s-log4shell-project-cluster-01
  metadata {
    name = "lacework"
  }
}

resource "lacework_agent_access_token" "log4shell-token" {
  name        = "log4shell-token" //TODO: revert to cluster name once suffix is added for uniqueness
  description = "k8s deployment for ${google_container_cluster.log4shell-project-cluster-01.name}"
}

module "lacework_k8s_datacollector" {
  source  = "lacework/agent/kubernetes"
  version = "~> 1.0"
  providers = {
    kubernetes = kubernetes.k8s-log4shell-project-cluster-01
  }

  lacework_access_token = lacework_agent_access_token.log4shell-token.token

  # Add the lacework_agent_tag argument to retrieve the cluster name in the Kubernetes Dossier
  lacework_agent_tags = { KubernetesCluster : "${google_container_cluster.log4shell-project-cluster-01.name}" }

  pod_cpu_request = "200m"
  pod_mem_request = "512Mi"
  pod_cpu_limit   = "1"
  pod_mem_limit   = "1024Mi"
}

// Networks 





// Outputs
output "log4shell-project-cluster-01-kubectl-command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.log4shell-project-cluster-01.name} --zone ${google_container_cluster.log4shell-project-cluster-01.location} --project ${module.log4shell-project.project_id}"
}
