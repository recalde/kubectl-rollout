#!/bin/bash
# This script retrieves Kubernetes deployments from a given namespace (or default),
# groups them by the label "app.kubernetes.io/instance",
# and prints an instance summary.
#
# For each instance, the output is:
#   Instance: <instance-label>
#   Deployments: deployment1: <replicas>, deployment2: <replicas>, ...
#   Total Replicas: <sum of replicas for that instance>
#
# Usage: ./instance_summary.sh [namespace]
#
# Requirements: kubectl must be configured and available in the PATH.

# Color codes for logging.
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"  # No Color

# Logging functions.
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Display banner header.
echo "====================================================="
echo "  Kubernetes Deployment Instance Summary"
echo "  (Grouped by app.kubernetes.io/instance)"
echo "====================================================="
echo ""

# Check for an optional namespace argument.
if [ $# -gt 0 ]; then
    NAMESPACE="$1"
    NAMESPACE_FLAG="-n ${NAMESPACE}"
    log_info "Filtering deployments in namespace: ${YELLOW}${NAMESPACE}${NC}"
else
    NAMESPACE_FLAG=""
    log_info "No namespace provided; using the default namespace."
fi

# Retrieve deployments.
log_info "Retrieving deployments (name, instance, replicas)..."
deployments=$(kubectl get deployments ${NAMESPACE_FLAG} -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.app\.kubernetes\.io/instance}{" "}{.spec.replicas}{"\n"}{end}')

if [ -z "$deployments" ]; then
    log_error "No deployments found. Exiting."
    exit 1
fi

# Declare associative arrays.
declare -A instance_deployments   # Will hold a concatenated string of "deployment: replica"
declare -A instance_totals        # Will hold the total replica count per instance

log_info "Processing deployments..."
while IFS=' ' read -r deploy instance replicas; do
    # Skip empty lines.
    [ -z "$deploy" ] && continue

    # Use default if instance label is missing.
    if [[ -z "$instance" ]]; then
        instance="unknown-instance"
    fi

    # Append the deployment detail (e.g., "webapp: 3") to the instance string.
    instance_deployments["$instance"]+="${deploy}: ${replicas}, "
    # Sum the total replicas for this instance.
    instance_totals["$instance"]=$(( ${instance_totals["$instance"]:-0} + replicas ))
    
    log_info "Processed deployment '${YELLOW}$deploy${NC}' with ${YELLOW}$replicas${NC} replicas under instance '${YELLOW}$instance${NC}'."
done <<< "$deployments"

# Display the summary for each instance.
echo ""
log_success "Instance Summary:"
echo "-----------------------------------------------------"
for instance in "${!instance_totals[@]}"; do
    echo -e "${YELLOW}Instance: ${instance}${NC}"
    # Remove trailing comma and space from the deployments string.
    deployments_str="${instance_deployments[$instance]}"
    deployments_str="${deployments_str%, }"
    echo "Deployments: ${deployments_str}"
    echo "Total Replicas: ${instance_totals[$instance]}"
    echo "-----------------------------------------------------"
done

log_success "Summary complete."