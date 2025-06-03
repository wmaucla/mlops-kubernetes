resource "helm_release" "psql" {
  name       = "psql"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = "15.2.5" # Latest as of June 2025

  namespace  = "default"

  set {
    name = "postgresqlPassword"
    value = "hello"
  }
}