resource "random_id" "suffix" {
  byte_length = 4
}

# Creates the project for our environment
module "log4shell-project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 10.3"

  name       = "log4shell-project-${random_id.suffix.hex}"
  project_id = "log4shell-project-${random_id.suffix.hex}"
  //TODO:  Refactor so that this is "parent", and can sense if there's an org or not
  org_id          = var.org_id
  folder_id       = var.folder_id != null ? var.folder_id : google_folder.main_folder[0].name
  billing_account = var.billing_account

  activate_apis = [
    "cloudbilling.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
  ]

  default_service_account = "deprivilege"
}
