terraform {
  required_version = "~>1.7.4"

  required_providers {
    helm = "~>2.9"
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~>1.14"
    }
    kubernetes = "~>2.30"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}
