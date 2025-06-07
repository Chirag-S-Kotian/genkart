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

# Prompt for client env variables
read "NEXT_PUBLIC_API?Enter NEXT_PUBLIC_API (e.g. http://34.100.196.196:5555/api): "
read "NEXT_PUBLIC_CLIENT_URL?Enter NEXT_PUBLIC_CLIENT_URL (e.g. http://34.100.196.196:3000/): "
read "NEXT_PUBLIC_JWT_SECRET?Enter NEXT_PUBLIC_JWT_SECRET: "
read "NEXT_PUBLIC_JWT_USER_SECRET?Enter NEXT_PUBLIC_JWT_USER_SECRET: "
read "NEXT_PUBLIC_NODE_ENV?Enter NEXT_PUBLIC_NODE_ENV (e.g. production): "

# Prompt for server env variables
read "MONGO_URI?Enter MONGO_URI: "
read "EMAIL_USER?Enter EMAIL_USER: "
read "EMAIL_PASS?Enter EMAIL_PASS: "
read "CLIENT_URL?Enter CLIENT_URL (e.g. http://34.100.196.196:3000): "
read "NODE_ENV?Enter NODE_ENV (e.g. production): "
read "CLOUDINARY_CLOUD_NAME?Enter CLOUDINARY_CLOUD_NAME: "
read "CLOUDINARY_API_KEY?Enter CLOUDINARY_API_KEY: "
read "CLOUDINARY_API_SECRET?Enter CLOUDINARY_API_SECRET: "
read "CLOUDINARY_FOLDER_NAME?Enter CLOUDINARY_FOLDER_NAME: "
read "JWT_SECRET?Enter JWT_SECRET: "
read "JWT_USER_SECRET?Enter JWT_USER_SECRET: "
read "JWT_EXPIRES_IN?Enter JWT_EXPIRES_IN (e.g. 1d): "

# Encode values to base64 (no newlines)
function b64() { echo -n "$1" | base64 | tr -d '\n'; }

cat > helm/templates/client-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: genkart-client-secrets
  labels:
    app: genkart-client
type: Opaque
data:
  NEXT_PUBLIC_API: $(b64 "$NEXT_PUBLIC_API")
  NEXT_PUBLIC_CLIENT_URL: $(b64 "$NEXT_PUBLIC_CLIENT_URL")
  NEXT_PUBLIC_JWT_SECRET: $(b64 "$NEXT_PUBLIC_JWT_SECRET")
  NEXT_PUBLIC_JWT_USER_SECRET: $(b64 "$NEXT_PUBLIC_JWT_USER_SECRET")
  NEXT_PUBLIC_NODE_ENV: $(b64 "$NEXT_PUBLIC_NODE_ENV")
EOF

cat > helm/templates/server-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: genkart-server-secrets
  labels:
    app: genkart-server
    app.kubernetes.io/managed-by: "Helm"
type: Opaque
data:
  MONGO_URI: $(b64 "$MONGO_URI")
  EMAIL_USER: $(b64 "$EMAIL_USER")
  EMAIL_PASS: $(b64 "$EMAIL_PASS")
  CLIENT_URL: $(b64 "$CLIENT_URL")
  NODE_ENV: $(b64 "$NODE_ENV")
  CLOUDINARY_CLOUD_NAME: $(b64 "$CLOUDINARY_CLOUD_NAME")
  CLOUDINARY_API_KEY: $(b64 "$CLOUDINARY_API_KEY")
  CLOUDINARY_API_SECRET: $(b64 "$CLOUDINARY_API_SECRET")
  CLOUDINARY_FOLDER_NAME: $(b64 "$CLOUDINARY_FOLDER_NAME")
  JWT_SECRET: $(b64 "$JWT_SECRET")
  JWT_USER_SECRET: $(b64 "$JWT_USER_SECRET")
  JWT_EXPIRES_IN: $(b64 "$JWT_EXPIRES_IN")
EOF

STEP=1
echo "\n[STEP $STEP] Authenticating to GKE..."
gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" --region "$GKE_REGION" --project "$GCP_PROJECT"

STEP=$((STEP+1))
echo "\n[STEP $STEP] Ensuring 'default' namespace exists..."
kubectl get ns default >/dev/null 2>&1 || kubectl create namespace default

STEP=$((STEP+1))
echo "\n[STEP $STEP] Updating Helm repos..."
helm repo update

STEP=$((STEP+1))
echo "\n[STEP $STEP] Checking and cleaning up pre-existing secrets that block Helm install..."
for secret in genkart-client-secrets genkart-server-secrets; do
  if kubectl get secret $secret -n default >/dev/null 2>&1; then
    MANAGED_BY=$(kubectl get secret $secret -n default -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null)
    if [ "$MANAGED_BY" != "Helm" ]; then
      echo "[WARN] Secret '$secret' exists in 'default' namespace and is not managed by Helm. Deleting it so Helm can manage it."
      kubectl delete secret $secret -n default
    fi
  fi
done

STEP=$((STEP+1))
echo "\n[STEP $STEP] Deploying Genkart app using Helm..."
if [ -f "helm/values-secret.yaml" ]; then
  helm upgrade --install genkart ./helm -f helm/values.yaml -f helm/values-secret.yaml --namespace default --create-namespace
  echo "[INFO] Genkart app deployed via Helm (with secrets)."
else
  echo "[WARN] helm/values-secret.yaml not found. Deploying without secrets file."
  helm upgrade --install genkart ./helm -f helm/values.yaml --namespace default --create-namespace
  echo "[INFO] Genkart app deployed via Helm (without secrets)."
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
echo "\n[STEP $STEP] Automated deployment complete!"
echo "To check status: kubectl get all -n default"
echo "To get client LoadBalancer IP: kubectl get svc genkart-client -n default"
echo "To get server service: kubectl get svc genkart-server -n default"
echo "\n[INFO] Done."
