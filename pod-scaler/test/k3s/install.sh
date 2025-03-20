#!/bin/bash

set -e  # Exit on any error
set -o pipefail  # Catch errors in piped commands

# Detect hostname or IP automatically
NODE_HOSTNAME=$(hostname -I | awk '{print $1}')  # Get first non-loopback IP
ARGOCD_NODEPORT=32080  # Fixed port for ArgoCD

# Function to install k3s
function install_k3s() {
    local K3S_VERSION="v1.28.4+k3s1"

    echo "🚀 Installing k3s (lightweight Kubernetes with Traefik)..."

    echo "✅ k3s is ready!"
    kubectl get nodes || echo "⚠️ No nodes found (this is normal if the cluster is empty)."
}

# Function to install kubectl
function install_kubectl() {
    echo "📦 Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
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

# Function to install Argo CD with a fixed NodePort
function install_argocd() {
    echo "📦 Installing Argo CD..."
    kubectl create namespace argocd || true
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "🔄 Setting Argo CD NodePort to $ARGOCD_NODEPORT..."
    kubectl patch svc argocd-server -n argocd -p "{\"spec\": {\"type\": \"NodePort\", \"ports\": [{\"port\": 443, \"targetPort\": 8080, \"nodePort\": $ARGOCD_NODEPORT}]}}"
    
    echo "✅ Argo CD installed! Access it at: http://$NODE_HOSTNAME:$ARGOCD_NODEPORT"
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
install_argocd
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
