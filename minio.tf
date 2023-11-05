resource "null_resource" "apply_minio_yaml" {
  triggers = {
    kubectl_apply = sha1(file("minio.yaml"))
  }

  provisioner "local-exec" {
    command = "kubectl apply -f minio.yaml"
  }
}