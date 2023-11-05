from diagrams import Cluster, Diagram, Edge
from diagrams.aws.storage import S3
from diagrams.custom import Custom
from diagrams.k8s.compute import Pod
from diagrams.k8s.infra import Node
from diagrams.onprem.client import Client, User
from diagrams.onprem.container import Docker
from diagrams.onprem.database import Postgresql
from diagrams.onprem.iac import Terraform
from diagrams.onprem.mlops import Mlflow
from diagrams.onprem.monitoring import Grafana, Prometheus
from diagrams.onprem.network import Envoy
from diagrams.onprem.queue import Kafka
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
        feast = Custom("Feast Feature Store", "./icons/feast.png")
        dataflow_pod = Pod("Metaflow Dataflow Pod")
        minikube = Node("Minikube Start")
        terraform = Terraform("Terraform Install")
        postgres = Postgresql("Postgres DB")
        minio_bucket = S3("Minio Bucket (mock S3)")
        mlflow = Mlflow("MLflow Registry")

        minikube >> terraform >> [postgres, minio_bucket]

        end_user = Client("End User")

        with Cluster("Seldon Installation"):
            seldon = Kubeflow("Seldon")
            model_deployment = Pod("MLServer Pod")
            ml_model = Custom("ML Model", "./icons/model.png")
            ml_model_challenger = Custom("ML Model Challenger", "./icons/model.png")
            kafka = Kafka("ML Data / Predictions")
            prom = Prometheus("Metrics")
            grafana = Grafana("Metrics")
            envoy = Envoy("Seldon Envoy")

            terraform >> seldon
            terraform >> [prom, grafana]
            seldon >> [prom, grafana]
            seldon >> model_deployment >> [ml_model, ml_model_challenger] >> kafka
            [ml_model, ml_model_challenger] >> envoy >> end_user
            kafka >> postgres

        minio_bucket >> Edge(color="brown") >> model_deployment

        dataflow_pod >> Edge(color="brown") >> feast >> Edge(color="brown") >> postgres
        (
            modelflow_pod
            >> Edge(color="brown")
            >> mlflow
            >> Edge(color="brown")
            >> minio_bucket
        )
        modelflow_pod >> Edge(color="brown") >> feast
        docker_container >> [modelflow_pod, dataflow_pod]
