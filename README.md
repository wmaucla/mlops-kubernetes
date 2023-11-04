# mlops-kubernetes

This repo is an experiment into creating a fully self-contained, local kubernetes deployment of a MLops cycle.

It involves:

1. Setting up a local k8s cluster via minikube
2. Postgres DB as a datastore
3. Metaflow for job orchestration
4. Feast for feature store implementation

## Versions

* Minikube for k8s cluster setup
    * minikube v1.31.2 on Ubuntu 22.04
    * Kubernetes v1.27.4 on Docker 24.0.4 
    * Helm version 3.10

* Terraform for IaC
    * 1.6.3

* K9s for ease of k8s management
    * 0.27.4


## Commands

1. Launching local minikube cluster:
```
minikube start
```

2. Launching terraform
```
terraform init
```

3. Installing postgres

TODO: migrate this to terraform
```
helm install psql --set postgresqlPassword=hello bitnami/postgresql
```

Helpful tips for postgres:

```
psql -h 10.244.0.69 -U postgres -d postgres -p 5432  # for connecting to the pod containing postgres
DROP DATABASE mydb; # for deleting db
```

In order to view password for postgres:

```
kubectl get secret --namespace default psql-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d
```
rJA6DQEUgo

Other, helpful commands:
```
kubectl port-forward --namespace default svc/psql-postgresql 5432:5432 &
    PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432
```

4. Building / testing out a job

Begin by building the docker image locally:

```bash
docker build -t pipeline .
```


```
eval $(minikube docker-env)
docker build -t bleh .
```