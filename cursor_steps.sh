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

# Step X: Ensure minio.yaml is applied (check via kubectl)
if ! kubectl get pods -l app=minio | grep -q Running; then
  echo "Minio pod not found or not running. Applying minio.yaml manually..."
  kubectl apply -f minio.yaml
else
  echo "Minio pod is already running."
fi


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
sed -i "/name: POSTGRES_HOST/{n;s/value: .*/value: \"$PSQL_POD_IP\"/}" metaflow_dataflow_pod.yaml

# Step 6c: Update POSTGRES_PASSWORD env in metaflow_dataflow_pod.yaml
POSTGRES_PASSWORD=$(kubectl get secret --namespace default psql-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Could not fetch Postgres password from secret!" >&2
  exit 1
fi
sed -i "/name: POSTGRES_PASSWORD/{n;s/value: .*/value: \"$POSTGRES_PASSWORD\"/}" metaflow_dataflow_pod.yaml

# Step 6d: Update password in feature_store.yaml
sed -i "12s/.*/    password: $POSTGRES_PASSWORD/" app/feast/feature_store.yaml

# Step 6e: Update password in the registry path in feature_store.yaml
sed -i "s|\(path: postgresql://postgres:\)[^@]*\(@.*\)|\1$POSTGRES_PASSWORD\2|" app/feast/feature_store.yaml

# Step 7: Build Docker image for pipeline inside Minikube's Docker
# Set Docker env to Minikube
eval $(minikube docker-env)
# Build the Docker image
if ! docker build -t pipeline .; then
  echo "Docker build failed. Exiting." >&2
  exit 1
fi

# Step 8: Apply metaflow_dataflow_pod.yaml and check pod status
if ! kubectl apply -f metaflow_dataflow_pod.yaml; then
  echo "Failed to apply metaflow_dataflow_pod.yaml. Exiting." >&2
  exit 1
fi

# Watch logs and status for metaflow-dataflow-pod
(
  echo "--- Streaming logs for metaflow-dataflow-pod (Ctrl+C to stop) ---"
  kubectl logs -f metaflow-dataflow-pod &
  LOG_PID=$!
  for i in {1..60}; do
    POD_STATUS=$(kubectl get pod metaflow-dataflow-pod -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "[Status check $i] metaflow-dataflow-pod status: $POD_STATUS"
    if [[ "$POD_STATUS" == "Succeeded" ]]; then
      echo "Pod completed successfully."
      kill $LOG_PID 2>/dev/null
      wait $LOG_PID 2>/dev/null
      exit 0
    fi
    if [[ "$POD_STATUS" == "Failed" ]]; then
      echo "ALERT: metaflow-dataflow-pod failed! Showing pod description and last logs:" >&2
      kill $LOG_PID 2>/dev/null
      wait $LOG_PID 2>/dev/null
      kubectl describe pod metaflow-dataflow-pod >&2
      kubectl logs metaflow-dataflow-pod >&2
      exit 1
    fi
    sleep 10
  done
  echo "Timeout waiting for pod to complete."
  kill $LOG_PID 2>/dev/null
  wait $LOG_PID 2>/dev/null
  exit 1
)

