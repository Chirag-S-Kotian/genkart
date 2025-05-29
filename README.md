# Genkart-Ecommerce

<!-- Badges -->
![Docker](https://img.shields.io/badge/Docker-ready-blue?logo=docker)
![Kubernetes](https://img.shields.io/badge/Kubernetes-ready-blue?logo=kubernetes)
![Helm](https://img.shields.io/badge/Helm-ready-blue?logo=helm)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-success?logo=argo)
![CI/CD](https://img.shields.io/badge/CI/CD-Automated-success?logo=githubactions)

---

<img src="./readme-assets/herosc.png" alt="" />
<img src="./readme-assets/exploresc.png" alt="" />
<img src="./readme-assets/productsc.png" alt="" />
<img src="./readme-assets/adminsc.png" alt="" />

---

## Table of Contents
- [Overview](#overview)
- [Tech Stack](#tech-stack)
- [Key Features](#key-features)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Clone the Repository](#clone-the-repository)
  - [Environment Variables](#environment-variables)
  - [Local Development](#local-development)
- [DevOps & Deployment](#devops--deployment)
  - [Docker & Docker Compose](#docker--docker-compose)
  - [Kubernetes](#kubernetes)
  - [Helm](#helm)
  - [ArgoCD GitOps](#argocd-gitops)
  - [Secret Management](#secret-management)
- [Developer & DevOps Commands](#developer--devops-commands)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

---

## Overview
Genkart is a sophisticated e-commerce platform designed to demonstrate a wide range of web development skills. Unlike traditional e-commerce sites, Genkart intentionally omits payment and "Buy Now" options, focusing instead on the user experience, product management, and robust backend functionality. The project is built using cutting-edge technologies and frameworks to ensure scalability, performance, and maintainability.

---

## Tech Stack
- **Frontend:** Next.js (React)
- **Backend:** Node.js, Express.js
- **Database:** MongoDB Atlas
- **Styling:** Tailwind CSS, Material UI, Material Tailwind
- **Image Management:** Cloudinary
- **DevOps:** Docker, Docker Compose, Kubernetes, Helm, ArgoCD

---

## Key Features
- **Authentication & Authorization:** JWT-based, role-based access (admin/customer)
- **Product Management:** CRUD for products/categories, Cloudinary image storage
- **User Profile:** Manage info, history, settings
- **Admin Panel:** Secure dashboard for managing products, categories, users

---

## Project Structure
```
Genkart/
├── client/           # Next.js frontend
├── server/           # Node.js/Express backend
├── helm/             # Helm chart for Kubernetes
├── k8s/              # Raw Kubernetes manifests
├── argocd/           # ArgoCD Application manifests
├── docker-compose.yaml
├── build-and-push.sh
├── README.md
└── ...
```

---

## Getting Started

### Requirements
- [Node.js](https://nodejs.org/en/download/package-manager)
- [Git](https://git-scm.com/downloads)
- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Kubernetes (Minikube or other)](https://minikube.sigs.k8s.io/docs/)
- [Helm](https://helm.sh/docs/intro/install/)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/getting_started/)

### Clone the Repository
```zsh
git clone https://github.com/Chirag-S-Kotian/genkart.git
cd genkart
```

### Environment Variables
- Copy `.env` templates from `/client/.env.example` and `/server/.env.example` (or create your own as described below).
- **Never commit secrets to Git!**

#### Example: `/client/.env`
```env
NEXT_PUBLIC_API='http://localhost:5000/api'
NEXT_PUBLIC_CLIENT_URL='http://localhost:5000/'
NEXT_PUBLIC_JWT_SECRET='adminfksnkzv'
NEXT_PUBLIC_JWT_USER_SECRET='usernsdbdskvn'
NEXT_PUBLIC_NODE_ENV='development'
```

#### Example: `/server/.env`
```env
MONGO_DB_URI="mongodb+srv://username:password@project.wvpqroq.mongodb.net/genkartv"
EMAIL_USER="genriotesting@gmail.com"
EMAIL_PASS="vivh ztpd snny zjda"
CLIENT_URL="http://localhost:3000"
NODE_ENV="production"
CLOUDINARY_CLOUD_NAME=""
CLOUDINARY_API_KEY=""
CLOUDINARY_API_SECRET=""
CLOUDINARY_FOLDER_NAME="Genkartv2"
JWT_SECRET="adminfksnkzv"
JWT_USER_SECRET="usernsdbdskvn"
JWT_EXPIRES_IN="1d"
```

### Local Development
#### Using Docker Compose
```zsh
docker-compose up --build
```
- Access client: http://localhost:3000
- Access server: http://localhost:5555

#### Using Node/NPM
```zsh
# Terminal 1
cd server
npm install
npm start

# Terminal 2
cd client
npm install
npm run dev
```

---

## DevOps & Deployment

### Docker & Docker Compose
- Build and push both images to Docker Hub:
  ```zsh
  ./build-and-push.sh
  ```
- Or build manually:
  ```zsh
  docker build -f client/next.dockerfile -t <user>/gen-client:v1 ./client
  docker build -f server/node.dockerfile -t <user>/gen-serv:v1 ./server
  docker push <user>/gen-client:v1 && docker push <user>/gen-serv:v1
  ```

### Kubernetes
- Deploy with raw manifests:
  ```zsh
  kubectl apply -f k8s/
  ```
- Delete all:
  ```zsh
  kubectl delete -f k8s/
  ```
- Get pods:
  ```zsh
  kubectl get pods
  ```
- Logs:
  ```zsh
  kubectl logs <pod>
  ```

### Helm
- Install/Upgrade:
  ```zsh
  helm upgrade --install genkart ./helm --namespace default --create-namespace
  ```
- Uninstall:
  ```zsh
  helm uninstall genkart --namespace default
  ```

### ArgoCD GitOps
1. **Install ArgoCD** (if not already):
   ```zsh
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
2. **Apply Application Manifest:**
   ```zsh
   kubectl apply -f argocd/genkart-app.yaml -n argocd
   ```
3. **Access ArgoCD UI:**
   ```zsh
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # Visit https://localhost:8080
   # Username: admin
   # Password: (see below)
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
   ```
4. **Sync & Manage:**
   - Login to ArgoCD UI, find `genkart` app, and sync or troubleshoot as needed.

### Secret Management
- **Do NOT commit real secrets to Git.**
- Use Helm's `values.yaml` for non-sensitive config, and external secret managers (e.g., [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), [External Secrets](https://external-secrets.io/)) for production.
- For local/dev, you can manually create secrets:
  ```zsh
  kubectl create secret generic genkart-client-secrets --from-literal=KEY=VALUE
  kubectl create secret generic genkart-server-secrets --from-literal=KEY=VALUE
  ```
- Or use the provided Helm templates and set values via `--set` or `-f mysecrets.yaml`.

---

## Developer & DevOps Commands

### Docker
- Build: `docker build -f client/next.dockerfile -t <user>/gen-client:v1 ./client`
- Build: `docker build -f server/node.dockerfile -t <user>/gen-serv:v1 ./server`
- Push: `docker push <user>/gen-client:v1 && docker push <user>/gen-serv:v1`

### Docker Compose
- Up: `docker-compose up --build`
- Down: `docker-compose down`

### Kubernetes
- Apply all: `kubectl apply -f k8s/`
- Delete all: `kubectl delete -f k8s/`
- Get pods: `kubectl get pods`
- Logs: `kubectl logs <pod>`

### Helm
- Install/Upgrade: `helm upgrade --install genkart ./helm --namespace default --create-namespace`
- Uninstall: `helm uninstall genkart --namespace default`

### ArgoCD
- Apply app: `kubectl apply -f argocd/genkart-app.yaml -n argocd`
- Delete app: `kubectl delete -f argocd/genkart-app.yaml -n argocd`
- Port-forward UI: `kubectl port-forward svc/argocd-server -n argocd 8080:443`

---

## Troubleshooting
- **Pods stuck in `CreateContainerConfigError`?**
  - Check if secrets exist: `kubectl get secrets`
  - Check pod logs: `kubectl logs <pod>`
  - Describe pod: `kubectl describe pod <pod>`
- **ArgoCD app out of sync?**
  - Sync manually in UI or with `kubectl`.
  - Check Application events in ArgoCD UI.
- **Helm secret not found?**
  - Ensure secret templates are rendered before deployments.
  - For production, use sealed/external secrets.

---

## Contributing
Pull requests and issues are welcome! Please open an issue for bugs or feature requests.

---

## License
This project is licensed under the terms of the MIT license. See [LICENSE](LICENSE) for details.

---

## Contact
**Chirag S Kotian**  
- GitHub: [Chirag-S-Kotian](https://github.com/Chirag-S-Kotian)
- LinkedIn: [chirag-s-kotian](https://www.linkedin.com/in/chirag-s-kotian/)
- Twitter: [@Chirag_S_kotian](https://twitter.com/Chirag_S_kotian)
- Email: chirag.mca.2024@pim.ac.in
- Website: [chirag-blockchian.vercel.app](https://chirag-blockchian.vercel.app/)

---

#

<!-- End of README -->
