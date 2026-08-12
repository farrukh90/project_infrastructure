terraform {
  backend "gcs" {
    bucket = "terraform-project-farrukh90"
    prefix = "project_infrastructure/2.tools_setup"
  }
}
