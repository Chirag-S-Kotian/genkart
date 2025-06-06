#!/bin/zsh
# Script to deploy ArgoCD and Genkart app to GKE using Helm and secrets
# Usage: ./deploy-argocd.sh <GCP_PROJECT> <GKE_CLUSTER_NAME> <GKE_REGION>

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

# Ensure step variable is always incremented and echoed
STEP=1
echo "\n[STEP $STEP] Authenticating to GKE..."
if ! kubectl config get-contexts | grep -q "$GKE_CLUSTER_NAME"; then
  gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" --region "$GKE_REGION" --project "$GCP_PROJECT"
else
  echo "[INFO] GKE context already set. Skipping authentication."
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Ensuring 'argocd' namespace exists..."
if ! kubectl get ns argocd >/dev/null 2>&1; then
  kubectl create namespace argocd
else
  echo "[INFO] Namespace 'argocd' already exists. Skipping."
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Adding/Updating ArgoCD Helm repo..."
if ! helm repo list | grep -q "argo"; then
  helm repo add argo https://argoproj.github.io/argo-helm
fi
helm repo update

STEP=$((STEP+1))
echo "\n[STEP $STEP] Checking for existing ArgoCD resources not managed by Helm..."
ARGOCD_HELM_RELEASE_EXISTS=$(helm -n argocd list | grep -c "argocd")
ARGOCD_K8S_RESOURCES_EXIST=$(kubectl get sa -n argocd argocd-application-controller --no-headers 2>/dev/null | wc -l)
if [ "$ARGOCD_HELM_RELEASE_EXISTS" -eq 0 ] && [ "$ARGOCD_K8S_RESOURCES_EXIST" -gt 0 ]; then
  echo "[WARN] ArgoCD resources exist in namespace 'argocd' but are not managed by Helm."
  echo "This can happen if you previously installed ArgoCD using kubectl apply."
  read "_CONFIRM?Do you want to delete all ArgoCD resources in 'argocd' and reinstall with Helm? (y/N): "
  if [[ $_CONFIRM =~ ^[Yy]$ ]]; then
    echo "Deleting all ArgoCD resources in 'argocd' namespace..."
    kubectl delete all,cm,secret,sa,role,rolebinding,svc,deploy,sts,rs,po -l app.kubernetes.io/part-of=argocd -n argocd || true
    sleep 5
  else
    echo "Aborting. Please clean up the namespace manually or use Helm to install only on a clean namespace."
    exit 10
  fi
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Installing ArgoCD via Helm if not already installed..."
if ! helm -n argocd list | grep -q "argocd"; then
  helm upgrade --install argocd argo/argo-cd --namespace argocd --set server.service.type=LoadBalancer
else
  echo "[INFO] ArgoCD already installed in namespace 'argocd'. Skipping Helm install."
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Waiting for ArgoCD server to be ready..."
if ! kubectl get deploy -n argocd argocd-server >/dev/null 2>&1; then
  echo "[ERROR] ArgoCD server deployment not found!"
  exit 2
fi
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

STEP=$((STEP+1))
echo "\n[STEP $STEP] Waiting for ArgoCD LoadBalancer IP..."
for i in {1..30}; do
  ARGOCD_LB_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  if [ -n "$ARGOCD_LB_IP" ]; then
    break
  fi
  sleep 10
done
if [ -z "$ARGOCD_LB_IP" ]; then
  echo "[ERROR] ArgoCD LoadBalancer IP not assigned."
  exit 3
fi
echo "[INFO] ArgoCD UI: http://$ARGOCD_LB_IP:80"

STEP=$((STEP+1))
echo "\n[STEP $STEP] Registering Genkart app with ArgoCD if not already registered..."
if ! kubectl get application -n argocd genkart >/dev/null 2>&1; then
  if [ -f "argocd/genkart-app.yaml" ]; then
    kubectl apply -f argocd/genkart-app.yaml
  else
    echo "[ERROR] argocd/genkart-app.yaml not found!"
    exit 4
  fi
else
  echo "[INFO] Genkart app already registered with ArgoCD. Skipping."
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Deploying Helm chart (with secrets) if not already deployed..."
if [ -f "helm/values-secret.yaml" ]; then
  if ! helm -n default list | grep -q "genkart"; then
    helm upgrade --install genkart ./helm -f helm/values.yaml -f helm/values-secret.yaml --namespace default --create-namespace
    echo "[INFO] Listing created secrets in 'default' namespace:"
    kubectl get secrets -n default | grep genkart || true
  else
    echo "[INFO] Genkart Helm release already exists in 'default' namespace. Skipping Helm deploy."
  fi
else
  echo "[ERROR] helm/values-secret.yaml not found! Please create this file with your secret values before deploying."
  exit 5
fi

STEP=$((STEP+1))
echo "\n[STEP $STEP] Deploying client and server secrets (if not managed by Helm)..."
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
echo "\n[STEP $STEP] Deployment complete!"
echo "ArgoCD UI: http://$ARGOCD_LB_IP:80"
echo "To get ArgoCD admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo "To port-forward (if no external IP):"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "To access your app, check your GKE LoadBalancer IPs."

exit 0
