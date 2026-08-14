provider "kubernetes" {
  config_path = pathexpand("~/.kube/config")
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand("~/.kube/config")
  }
}