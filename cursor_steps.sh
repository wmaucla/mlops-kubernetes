#!/bin/bash

# Step 1: Reboot minikube
minikube delete  # only delete if already exists
minikube start 

# Step 2: Initialize Terraform
# Wait for minikube to be ready
# sleep 30  # Adjust sleep time as necessary for minikube to be fully up
terraform init

# Step 3: Apply Terraform configuration
terraform apply -auto-approve

# Step 4: Wait for psql-postgresql pod to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql --timeout=120s

# Step 5: Get the internal IP of the psql-postgresql-0 pod
PSQL_POD_IP=$(kubectl get pod psql-postgresql-0 -o jsonpath='{.status.podIP}')
echo "PostgreSQL Pod IP: $PSQL_POD_IP"

if [ -z "$PSQL_POD_IP" ]; then
  echo "Could not find internal IP for psql-postgresql-0 pod." >&2
  exit 1
fi

# Step 6: Update feast feature_store.yaml with new IP
sed -i "s/^\(\s*host:\s*\).*/\1$PSQL_POD_IP/" app/feast/feature_store.yaml
sed -i "s|^\(\s*path: postgresql://postgres:[^@]*@\)[^:]*|\1$PSQL_POD_IP|" app/feast/feature_store.yaml

# Step 6b: Update POSTGRES_HOST env in metaflow_dataflow_pod.yaml
sed -i "s/\(name: POSTGRES_HOST\s*value: \).*/\1\"$PSQL_POD_IP\"/" metaflow_dataflow_pod.yaml

# Step 7: Build Docker image for pipeline inside Minikube's Docker
# Set Docker env to Minikube
eval $(minikube docker-env)
# Build the Docker image
if ! docker build -t pipeline .; then
  echo "Docker build failed. Exiting." >&2
  exit 1
fi


