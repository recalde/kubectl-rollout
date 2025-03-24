#!/bin/bash
# This script retrieves Kubernetes deployments from a given namespace (or default),
# groups them in a pivot table:
#   - Rows: app.kubernetes.io/instance label (or "unknown-instance" if missing)
#   - Columns: app.kubernetes.io/name label (or "unknown-name" if missing)
# The cell values are the sum of the configured replica counts.
#
# Usage: ./group_deployments.sh [namespace]
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
echo "==============================================================="
echo "  Kubernetes Deployment Replica Summary (Pivot Table)"
echo "  Rows: app.kubernetes.io/instance | Columns: app.kubernetes.io/name"
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
# Note: The dots in the jsonpath for labels are escaped.
deployments=$(kubectl get deployments ${NAMESPACE_FLAG} -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.app\.kubernetes\.io/instance}{" "}{.metadata.labels.app\.kubernetes\.io/name}{" "}{.spec.replicas}{"\n"}{end}')

if [ -z "$deployments" ]; then
    log_error "No deployments found. Exiting."
    exit 1
fi

# Declare associative arrays for our pivot table.
declare -A cell_values   # Key format: "instance|name"
declare -A row_totals    # Totals per instance (row)
declare -A col_totals    # Totals per name (column)

# Arrays to keep track of unique instances and name labels.
declare -A instance_seen
declare -A name_seen

log_info "Processing deployments..."
while IFS=' ' read -r deploy instance name replicas; do
    # Skip any empty lines.
    [ -z "$deploy" ] && continue

    # Use defaults if labels are missing.
    if [[ -z "$instance" ]]; then
        instance="unknown-instance"
    fi
    if [[ -z "$name" ]]; then
        name="unknown-name"
    fi

    # Use a composite key for the pivot table.
    key="${instance}|${name}"
    cell_values["$key"]=$(( ${cell_values["$key"]:-0} + replicas ))
    row_totals["$instance"]=$(( ${row_totals["$instance"]:-0} + replicas ))
    col_totals["$name"]=$(( ${col_totals["$name"]:-0} + replicas ))
    instance_seen["$instance"]=1
    name_seen["$name"]=1

    log_info "Deployment '${YELLOW}$deploy${NC}' with ${YELLOW}$replicas${NC} replicas (instance: ${YELLOW}$instance${NC}, name: ${YELLOW}$name${NC}) processed."
done <<< "$deployments"

# Build arrays of unique instances and names.
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

# Define column widths.
instanceWidth=20
colWidth=15
totalWidth=14

# Print the header row.
echo ""
log_success "Deployment Replica Pivot Table:"
printf "-------------------------------------------------------------------------------\n"
printf "| %-${instanceWidth}s " "Instance"
for nm in "${names[@]}"; do
    printf "| %-${colWidth}s " "$nm"
done
printf "| %-${totalWidth}s |\n" "Row Total"
printf "-------------------------------------------------------------------------------\n"

# Print each row for an instance.
for inst in "${instances[@]}"; do
    printf "| %-${instanceWidth}s " "$inst"
    for nm in "${names[@]}"; do
        key="${inst}|${nm}"
        value=${cell_values["$key"]:-0}
        printf "| %-${colWidth}d " "$value"
    done
    # Row total from our row_totals array.
    printf "| %-${totalWidth}d |\n" "${row_totals[$inst]}"
done

# Print the footer row with column totals.
printf "-------------------------------------------------------------------------------\n"
printf "| %-${instanceWidth}s " "Column Total"
for nm in "${names[@]}"; do
    printf "| %-${colWidth}d " "${col_totals[$nm]}"
done

# Compute overall total (sum of column totals).
overall_total=0
for nm in "${names[@]}"; do
    overall_total=$(( overall_total + col_totals["$nm"] ))
done
printf "| %-${totalWidth}d |\n" "$overall_total"
printf "-------------------------------------------------------------------------------\n"

log_success "Pivot table summary complete."