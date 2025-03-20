#!/bin/bash

set -e  # Exit on any error
set -o pipefail  # Catch errors in piped commands

# Function to display menu
function show_menu() {
    echo "🚀 Select the components you want to install:"
    options=("Kubernetes Dashboard" "Argo CD" "Helm" "Argo CD CLI" "k9s" "Nginx Ingress" "Cert-Manager" "Harbor Container Registry" "Lightweight Docker Registry" "Exit")
    defaults=(1 1 1 1 1 0 0 0 0)  # Default selections

    selected=("${defaults[@]}")

    while true; do
        clear
        echo "🔧 Use arrow keys + SPACE to select/deselect components. Press ENTER to continue."
        echo "[✔] k3s (Required - Always Installed)"
        for i in "${!options[@]}"; do
            if [[ "${selected[i]}" -eq 1 ]]; then
                echo "[✔] ${options[i]}"
            else
                echo "[ ] ${options[i]}"
            fi
        done
        
        read -p "Toggle selection (1-${#options[@]}) or press ENTER to continue: " choice
        
        if [[ -z "$choice" ]]; then
            break  # Proceed if user presses Enter
        elif [[ "$choice" =~ ^[1-9]$ ]]; then
            ((selected[choice-1]=!selected[choice-1]))  # Toggle selection
        elif [[ "$choice" == "10" ]]; then
            echo "❌ Exiting installer."
            exit 0
        else
            echo "⚠ Invalid option, try again."
            sleep 1
        fi
    done

    echo "✅ Selected components:"
    for i in "${!options[@]}"; do
        if [[ "${selected[i]}" -eq 1 ]]; then
            echo "   - ${options[i]}"
        fi
    done

    sleep 2
    clear

    install_k3s "${selected[@]}"
}

# Function to install k3s
function install_k3s() {
    local selected=("$@")
    K3S_VERSION="v1.28.4+k3s1"

    echo "🚀 Installing k3s (lightweight Kubernetes)..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -

    echo "🌎 Setting up KUBECONFIG for current user..."
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    export KUBECONFIG=~/.kube/config

    echo "🔄 Waiting for k3s to be ready..."
    sleep 10

    echo "✅ Verifying k3s cluster..."
    kubectl get nodes

    install_kubectl
    install_helm

    [[ "${selected[0]}" -eq 1 ]] && install_kubernetes_dashboard
    [[ "${selected[1]}" -eq 1 ]] && install_argocd
    [[ "${selected[2]}" -eq 1 ]] && install_helm
    [[ "${selected[3]}" -eq 1 ]] && install_argocd_cli
    [[ "${selected[4]}" -eq 1 ]] && install_k9s
    [[ "${selected[5]}" -eq 1 ]] && install_ingress
    [[ "${selected[6]}" -eq 1 ]] && install_cert_manager
    [[ "${selected[7]}" -eq 1 ]] && install_harbor
    [[ "${selected[8]}" -eq 1 ]] && install_docker_registry

    echo "🎉 Installation complete!"
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

# Function to install Argo CD
function install_argocd() {
    echo "📦 Installing Argo CD..."
    kubectl create namespace argocd || true
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo "✅ Argo CD installed!"
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

# Function to install Nginx Ingress
function install_ingress() {
    echo "📦 Installing Nginx Ingress..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
    echo "✅ Nginx Ingress installed!"
}

# Function to install Cert-Manager
function install_cert_manager() {
    echo "📦 Installing Cert-Manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
    echo "✅ Cert-Manager installed!"
}

# Function to install Harbor Container Registry
function install_harbor() {
    echo "📦 Installing Harbor Container Registry..."
    helm repo add harbor https://helm.goharbor.io
    helm repo update
    helm install harbor harbor/harbor --namespace harbor --create-namespace
    echo "✅ Harbor installed!"
}

# Function to install Lightweight Docker Registry
function install_docker_registry() {
    echo "📦 Installing Lightweight Docker Registry..."
    kubectl apply -f https://gist.githubusercontent.com/user/registry.yaml
    echo "✅ Docker Registry installed!"
}

# Start interactive installer
show_menu
