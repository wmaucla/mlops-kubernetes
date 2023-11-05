# mlops-kubernetes

<img alt="Python" src="https://img.shields.io/badge/python-3.10-blue.svg" /> </a>

[![][black-shield]][black]

[black]: http://github.com/psf/black
[black-shield]: https://img.shields.io/badge/code%20style-black-black.svg?style=for-the-badge&labelColor=gray


![Visual Studio Code](https://img.shields.io/badge/Visual%20Studio%20Code-0078d7.svg?style=for-the-badge&logo=visual-studio-code&logoColor=white) ![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Postgres](https://img.shields.io/badge/postgres-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)  ![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54) ![scikit-learn](https://img.shields.io/badge/scikit--learn-%23F7931E.svg?style=for-the-badge&logo=scikit-learn&logoColor=white) 
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white) ![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white) ![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)


While there are many examples that try and develop MLops, rarely are there repos that encapsulate that process end to end. This repo is an experiment into creating a fully self-contained, local kubernetes deployment of a MLops cycle. It showcases various ML tools and, more importantly, how they are managed.

## 🚀 Features 🚀

1. Setting up a local k8s cluster via minikube
2. Deploying postgres DB as a datastore
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

Start docker if necessary:
```bash
sudo dockerd
```

Then start minikube:
```bash
minikube start
```

2. Launching terraform

Make sure to set kube config variable first:

```bash
export KUBE_CONFIG_PATH=~/.kube/config
```

Now you can run terraform :

```bash
terraform init
terraform apply
```

This will install everything into the cluster


3. Building / testing out a job

Begin by making sure the local docker image can be built and accessible by minikube:

```bash
eval $(minikube docker-env)
```

<b> Note </b>
Currently the values for postgres DB are hardcoded, as they need to be accessible to pods within the cluster. Thus, all references to the host need to be replaced first. These are hardcoded in also to make it easier to understand the steps, whereas in practice they should be encrypted and never hardcoded.

E.g: 

* Go to the `feature_store.yaml` file within `app/feast`
* Find the current set host
* Find the IP of postgressql within the cluster
* Replace all instances with the new IP

Once that is done, do the same with the password. The password can be found via:

```bash
kubectl get secret --namespace default psql-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d
```

With an example value: 1ki6EsXo4s.

Replace all instances within the code w/ the new value.

Then build the docker image:

```bash
docker build -t pipeline .
```

Test out the dataflow pipeline:

```bash
kubectl apply -f metaflow_pod_dataflow.yaml
```



### Manual installations

This is only necessary if testing this out manually. The following notes are only kept from the development cycle:

#### Installing postgres

Helpful tips for postgres:

```
psql -h 10.244.0.3 -U postgres -d postgres -p 5432  # for connecting to the pod containing postgres
DROP DATABASE mydb; # for deleting db
```

In order to view password for postgres:

```
kubectl get secret --namespace default psql-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d
```


Other, helpful commands:
```
kubectl port-forward --namespace default svc/psql-postgresql 5432:5432 &
    PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432
```

For testing purposes an on iterations:

```bash
docker build -t pipeline . && kubectl delete -f metaflow_modelflow_pod.yaml && kubectl apply -f metaflow_modeflow_pod.yaml
```


