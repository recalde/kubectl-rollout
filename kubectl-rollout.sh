#!/bin/bash

set -e  # Exit on any error

# Record script start time
START_TIME=$(date +%s)

# Function to log messages with elapsed time
log() {
    local CURRENT_TIME=$(date +%s)
    local ELAPSED=$((CURRENT_TIME - START_TIME))
    local MINUTES=$((ELAPSED / 60))
    local SECONDS=$((ELAPSED % 60))
    printf "[%02d:%02d] %s\n" "$MINUTES" "$SECONDS" "$1"
}

scale_deployment() {
    local DEPLOYMENT_NAME=$1 TARGET_REPLICAS=$2 INCREMENT=$3 PAUSE=$4
    log "Starting rollout for $DEPLOYMENT_NAME (Target: $TARGET_REPLICAS, Increment: $INCREMENT, Pause: $PAUSE)"

    local CURRENT_REPLICAS
    CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT_NAME" -o=jsonpath='{.spec.replicas}')
    
    [[ -z "$CURRENT_REPLICAS" ]] && log "ERROR: Could not retrieve replica count for $DEPLOYMENT_NAME." && return 1

    while (( CURRENT_REPLICAS < TARGET_REPLICAS )); do
        local NEW_REPLICAS=$(( CURRENT_REPLICAS + INCREMENT > TARGET_REPLICAS ? TARGET_REPLICAS : CURRENT_REPLICAS + INCREMENT ))
        log "Scaling $DEPLOYMENT_NAME to $NEW_REPLICAS replicas..."
        kubectl scale deployment "$DEPLOYMENT_NAME" --replicas="$NEW_REPLICAS"
        (( NEW_REPLICAS < TARGET_REPLICAS )) && log "Waiting $PAUSE before next increment..." && sleep "$PAUSE"
        CURRENT_REPLICAS=$NEW_REPLICAS
    done

    log "Scaling complete for $DEPLOYMENT_NAME."
}

wait_for_deployment_ready() {
    log "Waiting for $1 to be fully rolled out..."
    kubectl rollout status deployment "$1"
    log "$1 is fully rolled out."
}

poll_pods_http() {
    local DEPLOYMENT_NAME=$1 ENDPOINT=$2 EXPECTED_SIZE=$3 RETRY_INTERVAL=5 MAX_RETRIES=5
    log "Polling pods for $DEPLOYMENT_NAME (Expected size: $EXPECTED_SIZE)..."

    # Fetch pod names and IPs for this deployment
    readarray -t PODS < <(kubectl get pods --field-selector=status.phase=Running -o=jsonpath="{range .items[?(@.metadata.ownerReferences[0].name=='$DEPLOYMENT_NAME')]}{.metadata.name} {.status.podIP}{"\n"}{end}")

    [[ ${#PODS[@]} -eq 0 ]] && log "ERROR: No running pods found for $DEPLOYMENT_NAME." && return 1

    for (( RETRIES=0; RETRIES < MAX_RETRIES && ${#PODS[@]} > 0; RETRIES++ )); do
        local NEXT_ROUND=()
        for POD in "${PODS[@]}"; do
            read -r POD_NAME POD_IP <<< "$POD"
            local URL="http://${POD_IP}${ENDPOINT}"
            log "Checking $URL for pod $POD_NAME..."
            RESPONSE=$(curl --max-time 10 -s "$URL" || echo "ERROR")
            [[ "$RESPONSE" == "ERROR" || ! "$RESPONSE" =~ "cluster-size: $EXPECTED_SIZE" ]] && NEXT_ROUND+=("$POD") && continue
            log "Pod $POD_NAME ($POD_IP) is ready!"
        done
        PODS=("${NEXT_ROUND[@]}")
        (( ${#PODS[@]} > 0 )) && log "Retrying ${#PODS[@]} failed pods in $RETRY_INTERVAL seconds..." && sleep $RETRY_INTERVAL
    done

    [[ ${#PODS[@]} -gt 0 ]] && log "WARNING: Some pods did not become ready: ${PODS[*]}" || log "All pods in $DEPLOYMENT_NAME are confirmed ready."
}

# Define deployments (format: "NAME EXPECTED_SIZE ENDPOINT INCREMENT PAUSE")
DEPLOYMENTS=(
    "app1 10 /api/v1/readiness 2 30s"
    "app2 5 /ready 3 20s"
    "app3 15 /status 2 40s"
)

# **Step 1: Scale Deployments**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
    read -r DEPLOYMENT EXPECTED_SIZE ENDPOINT INCREMENT PAUSE <<< "$APP_DATA"
    scale_deployment "$DEPLOYMENT" "$EXPECTED_SIZE" "$INCREMENT" "$PAUSE"
done

# **Step 2: Wait for Deployments to be Ready**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
    read -r DEPLOYMENT EXPECTED_SIZE ENDPOINT INCREMENT PAUSE <<< "$APP_DATA"
    wait_for_deployment_ready "$DEPLOYMENT"
done

# **Step 3: Poll Pods for Readiness**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
    read -r DEPLOYMENT EXPECTED_SIZE ENDPOINT INCREMENT PAUSE <<< "$APP_DATA"
    poll_pods_http "$DEPLOYMENT" "$ENDPOINT" "$EXPECTED_SIZE"
done
