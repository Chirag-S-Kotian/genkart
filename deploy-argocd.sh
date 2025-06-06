#!/bin/zsh
# Script to deploy Genkart app to GKE using Helm only (no ArgoCD)
# Usage: ./deploy-helm.sh <GCP_PROJECT> <GKE_CLUSTER_NAME> <GKE_REGION>

set -e

GCP_PROJECT="$1"
GKE_CLUSTER_NAME="$2"
GKE_REGION="$3"

if [ -z "$GCP_PROJECT" ] || [ -z "$GKE_CLUSTER_NAME" ] || [ -z "$GKE_REGION" ]; then
  echo "Usage: $0 <GCP_PROJECT> <GKE_CLUSTER_NAME> <GKE_REGION>"
  exit 1
fi

# Check for required tools
for tool in gcloud kubectl helm; do
  if ! command -v $tool >/dev/null 2>&1; then
    echo "[ERROR] $tool is not installed. Please install it before running this script."
    exit 1
  fi
  echo "[CHECK] $tool is installed."
done

STEP=1
echo "\n[STEP $STEP] Authenticating to GKE..."
gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" --region "$GKE_REGION" --project "$GCP_PROJECT"

STEP=$((STEP+1))
echo "\n[STEP $STEP] Ensuring 'default' namespace exists..."
kubectl get ns default >/dev/null 2>&1 || kubectl create namespace default

STEP=$((STEP+1))
echo "\n[STEP $STEP] Adding/Updating Helm repo (if needed)..."
# If you use a custom chart repo, add it here. For local charts, this is not needed.
helm repo update

STEP=$((STEP+1))
echo "\n[STEP $STEP] Deploying client and server secrets (if present)..."
if [ -f "helm/templates/client-secret.yaml" ]; then
  if ! kubectl get secret genkart-client-secrets -n default >/dev/null 2>&1; then
    kubectl apply -f helm/templates/client-secret.yaml -n default
    echo "[INFO] Client secrets deployed."
  else
    echo "[INFO] Client secret already exists. Skipping."
  fi
fi
if [ -f "helm/templates/server-secret.yaml" ]; then
  if ! kubectl get secret genkart-server-secrets -n default >/dev/null 2>&1; then
    kubectl apply -f helm/templates/server-secret.yaml -n default
    echo "[INFO] Server secrets deployed."
  else
    echo "[INFO] Server secret already exists. Skipping."
  fi
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Checking for pre-existing secrets that block Helm install..."
for secret in genkart-client-secrets genkart-server-secrets; do
  if kubectl get secret $secret -n default >/dev/null 2>&1; then
    # Check if managed by Helm
    MANAGED_BY=$(kubectl get secret $secret -n default -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null)
    if [ "$MANAGED_BY" != "Helm" ]; then
      echo "[WARN] Secret '$secret' exists in 'default' namespace and is not managed by Helm."
      echo "Deleting '$secret' so Helm can manage it."
      kubectl delete secret $secret -n default
    fi
  fi
done

STEP=$((STEP+1))
echo "\n[STEP $STEP] Deploying Genkart app using Helm..."
if [ -f "helm/values-secret.yaml" ]; then
  if ! helm -n default list | grep -q "genkart"; then
    helm upgrade --install genkart ./helm -f helm/values.yaml -f helm/values-secret.yaml --namespace default --create-namespace
    echo "[INFO] Genkart app deployed via Helm (with secrets)."
  else
    echo "[INFO] Genkart Helm release already exists in 'default' namespace. Upgrading..."
    helm upgrade genkart ./helm -f helm/values.yaml -f helm/values-secret.yaml --namespace default
  fi
else
  echo "[WARN] helm/values-secret.yaml not found. Deploying without secrets file."
  if ! helm -n default list | grep -q "genkart"; then
    helm upgrade --install genkart ./helm -f helm/values.yaml --namespace default --create-namespace
    echo "[INFO] Genkart app deployed via Helm (without secrets)."
  else
    echo "[INFO] Genkart Helm release already exists in 'default' namespace. Upgrading..."
    helm upgrade genkart ./helm -f helm/values.yaml --namespace default
  fi
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Waiting for client LoadBalancer IP..."
for i in {1..30}; do
  CLIENT_LB_IP=$(kubectl get svc genkart-client -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$CLIENT_LB_IP" ]; then
    break
  fi
  sleep 10
done
if [ -z "$CLIENT_LB_IP" ]; then
  echo "[WARN] Client LoadBalancer IP not assigned yet. Check with: kubectl get svc genkart-client -n default"
else
  echo "[INFO] Genkart Client UI: http://$CLIENT_LB_IP:3000"
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Deployment complete!"
echo "To check status: kubectl get all -n default"
echo "To get client LoadBalancer IP: kubectl get svc genkart-client -n default"
echo "To get server service: kubectl get svc genkart-server -n default"

echo "\n[INFO] Done."
