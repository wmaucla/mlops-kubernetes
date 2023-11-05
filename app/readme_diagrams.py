from diagrams import Cluster, Diagram, Edge
from diagrams.aws.storage import S3
from diagrams.custom import Custom
from diagrams.k8s.compute import Pod
from diagrams.k8s.infra import Node
from diagrams.onprem.client import Client, User
from diagrams.onprem.container import Docker
from diagrams.onprem.database import Postgresql
from diagrams.onprem.iac import Terraform
from diagrams.onprem.network import Envoy
from diagrams.onprem.workflow import Kubeflow
from diagrams.programming.language import Python

with Diagram("MLops Platform"):
    with Cluster("Local Development"):
        ds = User("Data Scientist")
        python = Python("Python Code")
        local_dataflow_code = Custom("Metaflow Dataflow", "./icons/metaflow.jpg")
        local_modelflow_code = Custom("Metaflow Modelflow", "./icons/metaflow.jpg")
        docker_container = Docker("Docker Image")

        ds >> python >> [local_dataflow_code, local_modelflow_code] >> docker_container

    with Cluster("Local Kubernetes Installation\n(Minikube)"):
        modelflow_pod = Pod("Metaflow Modelflow Pod")
        dataflow_pod = Pod("Metaflow Dataflow Pod")
        minikube = Node("Minikube Start")
        terraform = Terraform("Terraform Install")
        postgres = Postgresql("Postgres DB")
        minio_bucket = S3("Minio Bucket (mock S3)")

        minikube >> terraform >> [postgres, minio_bucket]

        end_user = Client("End User")

        with Cluster("Seldon Installation"):
            seldon = Kubeflow("Seldon")
            model_deployment = Pod("MLServer Pod")
            terraform >> seldon

            seldon >> model_deployment >> Envoy("Seldon Envoy") >> end_user

        minio_bucket >> Edge(color="brown") >> model_deployment

        dataflow_pod >> Edge(color="brown") >> postgres
        modelflow_pod >> Edge(color="brown") >> [minio_bucket, postgres]
        docker_container >> [modelflow_pod, dataflow_pod]
