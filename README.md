# mlops-kubernetes

<img alt="Python" src="https://img.shields.io/badge/python-3.10-blue.svg" /> </a>
<img alt="GitHub" src="https://img.shields.io/github/license/huggingface/transformers.svg?color=blue"> </a>
[![Ruff](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/astral-sh/ruff/main/assets/badge/v2.json)](https://github.com/astral-sh/ruff)
![Black](https://img.shields.io/badge/code%20style-black-000000.svg)


[black]: http://github.com/psf/black
[black-shield]: https://img.shields.io/badge/code%20style-black-black.svg?style=for-the-badge&labelColor=gray


![Visual Studio Code](https://img.shields.io/badge/Visual%20Studio%20Code-0078d7.svg?style=for-the-badge&logo=visual-studio-code&logoColor=white) ![Postgres](https://img.shields.io/badge/postgres-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)  ![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54) ![scikit-learn](https://img.shields.io/badge/scikit--learn-%23F7931E.svg?style=for-the-badge&logo=scikit-learn&logoColor=white) 

![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white) ![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white) ![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white) ![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)


This repo is an experiment into creating a fully self-contained, local kubernetes deployment of a MLops cycle. It showcases various ML tools and, more importantly, how they are managed. 

## 🚀 Features 🚀

1. Setting up a local k8s cluster via minikube
2. Deploying postgres DB as a datastore via terraform
3. Metaflow used job orchestration
4. Feast for feature store implementation
5. Seldon for model serving

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
kubectl apply -f metaflow_dataflow_pod.yaml
```

Within the kubernetes logs, you should see that the job executes successfully. Next, try the modelflow job:

```bash
kubectl apply -f metaflow_modelflow_pod.yaml
```

This job writes a model to a fake S3 bucket hosted by minio.

4. Setup fake minio bucket for model deployment

Normally seldon accesses s3/gcs buckets, granted permission using secrets. However, since this repo example is based purely on an internal, self-contained cluster, the rclone step needs to be configured specifically to read from our internal minio cluster.

Unfortunately this involves a small hack. We need to shell into the seldon modelserver pod and set the rclone config:

1. Edit the mlserver serverconfig to run as root (otherwise the config won't save)
2. restart mlserver statefulset deployment for changes to apply
3. Go onto the rclone container and update the config to allow for this new way of syncing:

This following script now points seldon's rclone to pull from our fake minio bucket
```bash
echo "[minio]
type = s3
provider = Minio
access_key_id = test-access-key
secret_access_key = test-secret-key
endpoint = http://10.244.0.42:9000" > /rclone/rclone.conf
```

5. Deploy model artifacts to cluster!

Port-forward the service account to be discoverable locally:
```bash
kubectl port-forward svc/seldon-mesh -n seldon-test 8080:80
```

Deploy the model to seldon via a kubectl command:

```bash
kubectl apply -f model.yaml
```

Now you can make a sample request to a model!
```bash
curl http://localhost:8080/v2/models/seldon-model/infer \
   -H "Content-Type: application/json" \
   -d '{"inputs": [{"name": "predict", "shape": [1, 4], "datatype": "FP32", "data": [[1, 2, 3, 4]]}]}'
```

Suppose you wanted to deploy a challenger model after a retraining; you can deploy it now via an experiment.

```bash
kubectl apply -f experiment.yaml
```

This example now shows how you can obtain an A/B split:

```bash
curl http://localhost:8080/v2/models/experiment-example/infer \
   -H "Content-Type: application/json" \
   -H "seldon-model: experiment-example.experiment" \
   -d '{"inputs": [{"name": "predict", "shape": [1, 4], "datatype": "FP32", "data": [[1, 2, 3, 4]]}]}'
```

Now we can run a sample batch of requests using 

```bash
python app/sample_requests.py
```

Note the output looks something like this:

```
Counter({'seldon-model-challenger_1': 40, 'seldon-model_1': 20}) example simulation of 60 requests
```

This shows that 40/60 requests went to the challenger model, 20/60 requests to the base model. We defined a 50/50 split, but obviously we need some more samples!

### Video Demo

<video controls>
  <source src="example_workflow.webm" type="video/webm">
  Your browser does not support the video tag.
</video>


### Manual installations

This is only necessary if testing this out manually. The following notes are only kept from the development cycle:

#### Installing postgres

Helpful tips for postgres:

```
psql -h 10.244.0.49 -U postgres -d postgres -p 5432  # for connecting to the pod containing postgres
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

#### Testing Jobs
For testing purposes an on iterations:

```bash
docker build -t pipeline . && kubectl delete -f metaflow_modelflow_pod.yaml && kubectl apply -f metaflow_modelflow_pod.yaml
```

#### Setting Rclone

For setting up rclone on the mlserver. Requires going into the rclone container and updating config

```bash
rclone config
```

Once running rclone config, here are some settings to try out:
```bash
minio
5 / Amazon compliant
16 / Minio

test-access-key
test-secret-key
http://10.244.0.49:9000
```

Once you have the config, you can test to make sure rclone is working correctly via:

```bash
rclone copy --config=/rclone/rclone.conf minio:demo-test-bucket/ temp/
```

