#!/bin/bash
# This script retrieves Kubernetes deployments from a given namespace (or default),
# groups them by the label "app.kubernetes.io/instance", and prints an instance summary.
#
# For each instance, the output includes:
#   - A header with the instance name.
#   - A single line listing each deployment (by name) and its replica count.
#   - A separate line showing the total replica count for that instance.
#
# Usage: ./instance_summary.sh [namespace]
# Requirements: kubectl must be configured and available in the PATH.

#-----------------------------
# Color codes for logging.
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"  # No Color

#-----------------------------
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

#-----------------------------
# Function to retrieve deployments using kubectl.
# The output will be a list with: <deployment> <instance label> <replica count>
get_deployments() {
    local ns_flag=""
    if [ -n "$NAMESPACE" ]; then
        ns_flag="-n ${NAMESPACE}"
    fi

    log_info "Retrieving deployments..."
    kubectl get deployments ${ns_flag} -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.app\.kubernetes\.io/instance}{" "}{.spec.replicas}{"\n"}{end}'
}

#-----------------------------
# Function to process deployments.
# It builds two global associative arrays:
#   - instance_deployments: maps instance -> string of "deployment: replicas"
#   - instance_totals: maps instance -> total replicas count
process_deployments() {
    local deployments_data="$1"

    # Declare global associative arrays.
    declare -gA instance_deployments
    declare -gA instance_totals

    while IFS=' ' read -r deploy instance replicas; do
        # Skip any empty lines.
        [ -z "$deploy" ] && continue

        # If the instance label is missing, use a default.
        if [[ -z "$instance" ]]; then
            instance="unknown-instance"
        fi

        # Ensure replicas is numeric; default to 0 if not.
        if ! [[ "$replicas" =~ ^[0-9]+$ ]]; then
            replicas=0
        fi

        # Append deployment info (e.g., "webapp: 3") to the instance summary.
        instance_deployments["$instance"]+="${deploy}: ${replicas}, "
        # Sum up replicas for the instance.
        instance_totals["$instance"]=$(( ${instance_totals["$instance"]:-0} + replicas ))
        
        log_info "Processed deployment '${deploy}' with ${replicas} replicas under instance '${instance}'."
    done <<< "$deployments_data"
}

#-----------------------------
# Function to print the instance summary.
# For each instance, prints a header, a line with deployment details, and the total replicas.
print_instance_summary() {
    echo ""
    log_success "Instance Summary:"
    echo "-----------------------------------------------------"
    for instance in "${!instance_totals[@]}"; do
        echo -e "${YELLOW}Instance: ${instance}${NC}"
        # Remove trailing comma and space.
        local deployments_str="${instance_deployments[$instance]%, }"
        echo "Deployments: ${deployments_str}"
        echo "Total Replicas: ${instance_totals[$instance]}"
        echo "-----------------------------------------------------"
    done
}

#-----------------------------
# Main script execution.
# Optionally accepts a namespace parameter.
if [ $# -gt 0 ]; then
    NAMESPACE="$1"
    log_info "Filtering deployments in namespace: ${YELLOW}${NAMESPACE}${NC}"
else
    log_info "No namespace provided; using the default namespace."
fi

deployments_data=$(get_deployments)

if [ -z "$deployments_data" ]; then
    log_error "No deployments found. Exiting."
    exit 1
fi

process_deployments "$deployments_data"
print_instance_summary

log_success "Summary complete."