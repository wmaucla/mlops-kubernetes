resource "kubernetes_namespace" "seldon_test" {
  metadata {
    labels = {
      name = "seldon"
    }
    name = "seldon-test"
  }
}

resource "helm_release" "seldon_core_v2_crds" {
  name = "seldon-core-v2-crds"

  repository = "https://seldonio.github.io/helm-charts"
  chart      = "seldon-core-v2-crds"
  version    = "2.6.0"
  timeout    = 1200

  depends_on = [
    kubernetes_namespace.seldon_test
  ]
}

resource "helm_release" "seldon_core_v2_runtime" {
  name = "seldon-core-v2-runtime"

  repository = "https://seldonio.github.io/helm-charts"
  chart      = "seldon-core-v2-runtime"
  version    = "2.6.0"
  namespace  = kubernetes_namespace.seldon_test.id
  timeout    = 1200

  depends_on = [
    helm_release.seldon_core_v2_crds
  ]
}


resource "helm_release" "seldon_core_v2_setup" {
  name = "seldon-core-v2-setup"

  repository = "https://seldonio.github.io/helm-charts"
  chart      = "seldon-core-v2-setup"
  version    = "2.6.0"
  namespace  = kubernetes_namespace.seldon_test.id
  timeout    = 1200

  depends_on = [
    helm_release.seldon_core_v2_crds
  ]
}

resource "helm_release" "seldon_core_v2_servers" {
  name = "seldon-core-v2-servers"

  repository = "https://seldonio.github.io/helm-charts"
  chart      = "seldon-core-v2-servers"
  version    = "2.5.0"
  namespace  = kubernetes_namespace.seldon_test.id
  timeout    = 1200

  depends_on = [
    helm_release.seldon_core_v2_setup
  ]
}