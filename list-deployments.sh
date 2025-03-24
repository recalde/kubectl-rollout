#!/bin/bash
# This script retrieves Kubernetes deployments (optionally for a given namespace),
# groups them by the label "app.kubernetes.io/instance", and prints an instance summary.
# For each instance, it shows a header, a line listing each deployment and its replica count,
# and a separate line with the total replicas for that instance.
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
# Function to retrieve deployments.
# Returns lines of: <deployment> <instance label> <replica count>
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
# Builds two global associative arrays:
#   - instance_deployments: maps instance -> concatenated string of "deployment: replicas"
#   - instance_totals: maps instance -> total replicas (as a number)
process_deployments() {
    local deployments_data="$1"
    declare -gA instance_deployments
    declare -gA instance_totals

    while IFS=' ' read -r deploy instance replicas; do
        [ -z "$deploy" ] && continue

        # If the instance label is missing, use a default.
        if [[ -z "$instance" ]]; then
            instance="unknown-instance"
        fi

        # Remove any non-digit characters from replicas.
        replicas=$(echo "$replicas" | tr -cd '0-9')
        if [ -z "$replicas" ]; then
            replicas=0
        fi

        # Append deployment info to the instance string.
        instance_deployments["$instance"]+="${deploy}: ${replicas}, "
        
        # Get the current total for this instance (defaulting to 0) and add replicas.
        current_total=${instance_totals["$instance"]}
        if ! [[ "$current_total" =~ ^[0-9]+$ ]]; then
            current_total=0
        fi
        instance_totals["$instance"]=$(( current_total + replicas ))
        
        log_info "Processed deployment '${deploy}' with ${replicas} replicas under instance '${instance}'."
    done <<< "$deployments_data"
}

#-----------------------------
# Function to print the instance summary.
# For each instance, prints:
#   - The instance header
#   - A line with each deployment and its replica count
#   - A line with the total replicas for that instance
print_instance_summary() {
    echo ""
    log_success "Instance Summary:"
    echo "-----------------------------------------------------"
    for instance in "${!instance_totals[@]}"; do
        echo -e "${YELLOW}Instance: ${instance}${NC}"
        local deployments_str="${instance_deployments[$instance]%, }"  # remove trailing comma and space
        echo "Deployments: ${deployments_str}"
        echo "Total Replicas: ${instance_totals[$instance]}"
        echo "-----------------------------------------------------"
    done
}

#-----------------------------
# Main execution.
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