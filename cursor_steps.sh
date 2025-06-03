#!/bin/bash

# Step 1: Reboot minikube
minikube delete  # only delete if already exists
minikube start --cpus=4 --memory=16384

# Step 2: Initialize Terraform
# Wait for minikube to be ready
# sleep 30  # Adjust sleep time as necessary for minikube to be fully up
terraform init

# Step 3: Apply Terraform configuration
terraform apply -auto-approve

# Step 4: Wait for psql-postgresql pod to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql --timeout=120s

# Function to wait for MinIO pod and get its IP
wait_for_minio_pod() {
    local max_attempts=9  # 9 attempts * 60 seconds = 9 minutes maximum wait
    local attempt=1
    
    echo "Waiting for MinIO pod to be ready and get its IP..."
    
    while [ $attempt -le $max_attempts ]; do
        # Check if MinIO pod exists and is running
        if kubectl get pods -n default | grep -q "minio-deployment.*Running"; then
            MINIO_POD_NAME=$(kubectl get pods | grep "minio-deployment" | awk '{print $1}')
            MINIO_POD_IP=$(kubectl get pod $MINIO_POD_NAME -o jsonpath='{.status.podIP}')
            
            if [ ! -z "$MINIO_POD_IP" ]; then
                echo "MinIO Pod IP found: $MINIO_POD_IP"
                return 0
            fi
        fi
        
        echo "Attempt $attempt/$max_attempts: MinIO pod not ready or IP not available yet. Waiting 20 seconds and retrying..."
        sleep 60
        attempt=$((attempt + 1))
    done
    
    echo "Timed out waiting for MinIO pod IP after $max_attempts attempts"
    return 1
}

# Step X: Ensure minio.yaml is applied (check via kubectl)
if ! kubectl get pods | grep -q "minio-deployment.*Running"; then
  echo "Minio pod not found or not running. Applying minio.yaml manually..."
  kubectl apply -f minio.yaml
else
  echo "Minio pod is already running."
fi

# Wait for MinIO pod and get its IP
if ! wait_for_minio_pod; then
  echo "Failed to get MinIO pod IP. Exiting." >&2
  exit 1
fi

# Update MINIO_ENDPOINT in metaflow_modelflow_pod.yaml
sed -i "/name: MINIO_ENDPOINT/{n;s|value:.*|value: \"http://$MINIO_POD_IP:9000\"|}" metaflow_modelflow_pod.yaml

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
      break
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

# Step 9: Apply metaflow_modelflow_pod.yaml and check pod status
if ! kubectl apply -f metaflow_modelflow_pod.yaml; then
  echo "Failed to apply metaflow_modelflow_pod.yaml. Exiting." >&2
  exit 1
fi

# Watch logs and status for metaflow-modelflow-pod
(
  echo "--- Streaming logs for metaflow-modelflow-pod (Ctrl+C to stop) ---"
  kubectl logs -f metaflow-modelflow-pod &
  LOG_PID=$!
  for i in {1..60}; do
    POD_STATUS=$(kubectl get pod metaflow-modelflow-pod -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "[Status check $i] metaflow-modelflow-pod status: $POD_STATUS"
    if [[ "$POD_STATUS" == "Succeeded" ]]; then
      echo "Pod completed successfully."
      kill $LOG_PID 2>/dev/null
      wait $LOG_PID 2>/dev/null
      exit 0
    fi
    if [[ "$POD_STATUS" == "Failed" ]]; then
      echo "ALERT: metaflow-modelflow-pod failed! Showing pod description and last logs:" >&2
      kill $LOG_PID 2>/dev/null
      wait $LOG_PID 2>/dev/null
      kubectl describe pod metaflow-modelflow-pod >&2
      kubectl logs metaflow-modelflow-pod >&2
      exit 1
    fi
    sleep 10
  done
  echo "Timeout waiting for pod to complete."
  kill $LOG_PID 2>/dev/null
  wait $LOG_PID 2>/dev/null
  exit 1
)

# Step 14: Check that mlserver-0 pod is up and ready
echo "Checking that mlserver-0 pod is up and ready..."
kubectl wait --for=condition=ready pod/mlserver-0 -n seldon-test --timeout=600s

# Step 15: Apply example_model.yaml
echo "Applying example_model.yaml..."
kubectl apply -f example_model.yaml

# Step 11: Port-forward the model service
echo "Port-forwarding the example model service..."
kubectl port-forward svc/seldon-mesh -n seldon-test 8080:80 &
PORT_FORWARD_PID=$!
sleep 5  # Give port-forward time to start

# Step 12: Make a sample request and get the output
echo "Making a sample request to the example model..."
curl -s -X POST "http://localhost:8080/v2/models/iris/infer" -H "Content-Type: application/json" -d '{"inputs": [{"name": "input-0", "shape": [1, 4], "datatype": "FP32", "data": [[1.0, 2.0, 3.0, 4.0]]}]}'

# Kill the port-forward process
echo "Killing port-forward process..."
kill $PORT_FORWARD_PID


