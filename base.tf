terraform {
  required_version = "~>1.6.1"

  required_providers {
    helm        = "~>2.9"
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~>1.14"
    }
    kubernetes = "~>2.21"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}
