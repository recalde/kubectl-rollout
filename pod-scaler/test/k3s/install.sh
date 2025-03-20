#!/bin/bash

set -e  # Exit on any error
set -o pipefail  # Catch errors in piped commands

# Detect hostname or IP automatically
NODE_HOSTNAME=$(hostname -I | awk '{print $1}')  # Get first non-loopback IP
ARGOCD_NODEPORT=32080  # Fixed port for ArgoCD

# Default installation options (1 = install, 0 = skip)
INSTALL_DASHBOARD=1
INSTALL_ARGOCD=1
INSTALL_HELM=1
INSTALL_ARGOCD_CLI=1
INSTALL_K9S=1
INSTALL_DOCKER_REGISTRY=1
INSTALL_PROMETHEUS=1
INSTALL_GRAFANA=1
INSTALL_LOKI=1

# Function to install k3s
function install_k3s() {
    local K3S_VERSION="v1.28.4+k3s1"

    echo "🚀 Installing k3s (lightweight Kubernetes with Traefik)..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -

    echo "🌎 Setting up KUBECONFIG for current user..."
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    export KUBECONFIG=~/.kube/config

    echo "🔄 Waiting for k3s API server to be ready..."
    ATTEMPTS=0
    while ! kubectl get nodes &>/dev/null; do
        ((ATTEMPTS++))
        if [[ $ATTEMPTS -gt 20 ]]; then
            echo "❌ k3s did not start in time. Check 'sudo journalctl -u k3s' for logs."
            exit 1
        fi
        echo "⏳ Waiting for k3s to become ready... (Attempt $ATTEMPTS/20)"
        sleep 5
    done

    echo "✅ k3s is ready!"
    kubectl get nodes
}

# Function to install kubectl
function install_kubectl() {
    echo "📦 Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo "✅ kubectl installed!"
}

# Function to install Helm
function install_helm() {
    echo "📦 Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "✅ Helm installed!"
}

# Function to install Kubernetes Dashboard
function install_kubernetes_dashboard() {
    echo "📦 Installing Kubernetes Dashboard..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
    echo "✅ Kubernetes Dashboard installed!"
}

# Function to install Argo CD with a fixed NodePort
function install_argocd() {
    echo "📦 Installing Argo CD..."
    kubectl create namespace argocd || true
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "🔄 Setting Argo CD NodePort to $ARGOCD_NODEPORT..."
    kubectl patch svc argocd-server -n argocd -p "{\"spec\": {\"type\": \"NodePort\", \"ports\": [{\"port\": 443, \"targetPort\": 8080, \"nodePort\": $ARGOCD_NODEPORT}]}}"
    
    echo "✅ Argo CD installed! Access it at: http://$NODE_HOSTNAME:$ARGOCD_NODEPORT"
}

# Function to install Argo CD CLI
function install_argocd_cli() {
    echo "📦 Installing Argo CD CLI..."
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x argocd-linux-amd64
    sudo mv argocd-linux-amd64 /usr/local/bin/argocd
    echo "✅ Argo CD CLI installed!"
}

# Function to install k9s
function install_k9s() {
    echo "📦 Installing k9s..."
    curl -sS https://webinstall.dev/k9s | bash
    echo "✅ k9s installed!"
}

# Function to install Prometheus, Grafana, and Loki (Using Traefik)
function install_monitoring_stack() {
    echo "📦 Installing Prometheus, Grafana, and Loki (Traefik enabled)..."

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    # Install Prometheus
    helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

    # Install Loki
    helm install loki grafana/loki-stack --namespace monitoring --set promtail.enabled=true

    echo "✅ Prometheus, Grafana, and Loki installed!"
}

### **🚀 Run Installation Steps**
install_k3s
install_kubectl
install_helm
install_kubernetes_dashboard
install_argocd
install_argocd_cli
install_k9s
install_monitoring_stack

echo "🎉 Installation complete! 🚀"

echo "🌍 **Access Your Services Here:**"
echo "🔹 **Argo CD**:      http://$NODE_HOSTNAME:$ARGOCD_NODEPORT"
echo "🔹 **Grafana**:      http://grafana.local (set up via Traefik)"
echo "🔹 **Prometheus**:   Accessible via Grafana"
echo "🔹 **Loki (Logs)**:  Integrated with Grafana"

echo "✅ **Login to Argo CD**"
echo "   Username: admin"
echo "   Password: (Use: kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
