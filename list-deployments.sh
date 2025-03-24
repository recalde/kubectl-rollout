#!/bin/bash
# This script retrieves Kubernetes deployments in a given namespace (or default),
# groups them by the label "app.kubernetes.io/instance",
# and prints a friendly summary of the configured replica count for each group.

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
echo "=========================================="
echo "  Kubernetes Deployment Replica Summary"
echo "     (Grouped by app.kubernetes.io/instance)"
echo "=========================================="
echo ""

# Check for an optional namespace argument.
if [ $# -gt 0 ]; then
    NAMESPACE="$1"
    NAMESPACE_FLAG="-n ${NAMESPACE}"
    log_info "Using namespace filter: ${YELLOW}${NAMESPACE}${NC}"
else
    NAMESPACE_FLAG=""
    log_info "No namespace provided; using the default namespace."
fi

# Retrieve deployments using kubectl.
log_info "Retrieving deployments..."
# The jsonpath extracts: deployment name, label 'app.kubernetes.io/instance', and replicas.
deployments=$(kubectl get deployments ${NAMESPACE_FLAG} -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.app\.kubernetes\.io/instance}{" "}{.spec.replicas}{"\n"}{end}')

if [ -z "$deployments" ]; then
    log_error "No deployments found. Exiting."
    exit 1
fi

# Declare an associative array to hold the sum of replicas per instance.
declare -A group_summary

log_info "Processing deployments..."
while IFS=' ' read -r name instance replicas; do
    # Skip empty lines.
    [ -z "$name" ] && continue

    # If the instance label is missing, group it as "unknown"
    if [[ -z "$instance" ]]; then
      instance="unknown"
    fi

    # Sum up replicas for this instance.
    group_summary["$instance"]=$(( ${group_summary["$instance"]:-0} + replicas ))
    log_info "Added deployment '${YELLOW}$name${NC}' with ${YELLOW}$replicas${NC} replicas under instance '${YELLOW}$instance${NC}'."
done <<< "$deployments"

# Print a friendly summary table.
echo ""
log_success "Deployment Replica Summary (Grouped by Instance):"
printf "---------------------------------------------------------\n"
printf "| %-25s | %-14s |\n" "Instance" "Total Replicas"
printf "---------------------------------------------------------\n"
for instance in "${!group_summary[@]}"; do
    printf "| %-25s | %-14d |\n" "$instance" "${group_summary["$instance"]}"
done
printf "---------------------------------------------------------\n"

log_success "Summary complete."
