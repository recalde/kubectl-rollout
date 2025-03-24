#!/bin/bash
# This script retrieves Kubernetes deployments from a given namespace (or default),
# groups them by the label "app.kubernetes.io/instance" (each instance gets its own table),
# and within each table, displays columns for each "app.kubernetes.io/name" value showing the replica counts.
#
# Deployments missing a label are grouped under "unknown-instance" or "unknown-name".
# Friendly logging with colored messages is provided throughout.

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
echo "==============================================================="
echo "  Kubernetes Deployment Replica Summary (Separate Tables)"
echo "  Each table groups columns by app.kubernetes.io/name"
echo "  for a given app.kubernetes.io/instance"
echo "==============================================================="
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
log_info "Retrieving deployments (name, instance label, name label, replicas)..."
# Escape dots in label names.
deployments=$(kubectl get deployments ${NAMESPACE_FLAG} -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.app\.kubernetes\.io/instance}{" "}{.metadata.labels.app\.kubernetes\.io/name}{" "}{.spec.replicas}{"\n"}{end}')

if [ -z "$deployments" ]; then
    log_error "No deployments found. Exiting."
    exit 1
fi

# Declare associative arrays for our pivot data.
declare -A cell_values   # Key format: "instance|name" holds the replica count.
declare -A row_totals    # Totals per instance (row).

# We'll also track all unique instance and name labels.
declare -A instance_seen
declare -A name_seen

log_info "Processing deployments..."
while IFS=' ' read -r deploy instance name replicas; do
    # Skip empty lines.
    [ -z "$deploy" ] && continue

    # Use default values if labels are missing.
    if [[ -z "$instance" ]]; then
        instance="unknown-instance"
    fi
    if [[ -z "$name" ]]; then
        name="unknown-name"
    fi

    # Create a composite key for the pivot data.
    key="${instance}|${name}"
    cell_values["$key"]=$(( ${cell_values["$key"]:-0} + replicas ))
    row_totals["$instance"]=$(( ${row_totals["$instance"]:-0} + replicas ))
    instance_seen["$instance"]=1
    name_seen["$name"]=1

    log_info "Processed deployment '${YELLOW}$deploy${NC}' with ${YELLOW}$replicas${NC} replicas (instance: ${YELLOW}$instance${NC}, name: ${YELLOW}$name${NC})."
done <<< "$deployments"

# Build arrays of unique instance and name labels.
instances=()
for inst in "${!instance_seen[@]}"; do
    instances+=( "$inst" )
done

names=()
for nm in "${!name_seen[@]}"; do
    names+=( "$nm" )
done

# (Optional) Sort the arrays for consistent output.
IFS=$'\n' instances=($(sort <<<"${instances[*]}"))
IFS=$'\n' names=($(sort <<<"${names[*]}"))
unset IFS

# Define formatting widths.
colWidth=15
totalWidth=14

# For each instance, print a separate table.
for inst in "${instances[@]}"; do
    echo ""
    log_success "Pivot Table for Instance: ${YELLOW}$inst${NC}"
    
    # Print table header.
    printf "-------------------------------------------------------------\n"
    printf "|"
    for nm in "${names[@]}"; do
        printf " %-${colWidth}s |" "$nm"
    done
    printf " %-${totalWidth}s |\n" "Total"
    printf "-------------------------------------------------------------\n"
    
    # Print table row for the instance.
    printf "|"
    row_total=0
    for nm in "${names[@]}"; do
        key="${inst}|${nm}"
        value=${cell_values["$key"]:-0}
        printf " %-${colWidth}d |" "$value"
    done
    printf " %-${totalWidth}d |\n" "${row_totals[$inst]}"
    printf "-------------------------------------------------------------\n"
done

log_success "Summary tables complete."