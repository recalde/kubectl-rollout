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
    local DEPLOYMENT_NAME=$1 INSTANCE=$2 NAME=$3 TARGET_REPLICAS=$4 INCREMENT=$5 PAUSE=$6
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
    local DEPLOYMENT_NAME=$1 INSTANCE=$2 NAME=$3 ENDPOINT=$4 PORT=$5 EXPECTED_SIZE=$6 RETRY_INTERVAL=5 MAX_RETRIES=5
    log "Polling pods for $DEPLOYMENT_NAME (Expected size: $EXPECTED_SIZE) on port $PORT..."

    # Fetch pod names & IPs using label selectors (ensuring we get only running pods)
    readarray -t PODS < <(kubectl get pods -l "app.kubernetes.io/instance=${INSTANCE},app.kubernetes.io/name=${NAME}" \
        --field-selector=status.phase=Running -o=jsonpath="{range .items[*]}{.metadata.name} {.status.podIP}{'\n'}{end}")

    [[ ${#PODS[@]} -eq 0 ]] && log "ERROR: No running pods found for $DEPLOYMENT_NAME." && return 1

    for (( RETRIES=0; RETRIES < MAX_RETRIES && ${#PODS[@]} > 0; RETRIES++ )); do
        local NEXT_ROUND=()
        for POD in "${PODS[@]}"; do
            read -r POD_NAME POD_IP <<< "$POD"
            [[ -z "$POD_IP" ]] && log "ERROR: Could not retrieve IP for pod $POD_NAME." && NEXT_ROUND+=("$POD_NAME") && continue
            local URL="http://${POD_IP}:${PORT}${ENDPOINT}"
            log "Checking $URL for pod $POD_NAME..."
            RESPONSE=$(curl --max-time 10 -s "$URL" || echo "ERROR")
            [[ "$RESPONSE" == "ERROR" || ! "$RESPONSE" =~ "cluster-size: $EXPECTED_SIZE" ]] && NEXT_ROUND+=("$POD_NAME") && continue
            log "Pod $POD_NAME ($POD_IP) is ready!"
        done
        PODS=("${NEXT_ROUND[@]}")
        (( ${#PODS[@]} > 0 )) && log "Retrying ${#PODS[@]} failed pods in $RETRY_INTERVAL seconds..." && sleep $RETRY_INTERVAL
    done

    [[ ${#PODS[@]} -gt 0 ]] && log "WARNING: Some pods did not become ready: ${PODS[*]}" || log "All pods in $DEPLOYMENT_NAME are confirmed ready."
}

# Define deployments (format: "DEPLOYMENT INSTANCE NAME EXPECTED_SIZE ENDPOINT PORT INCREMENT PAUSE")
DEPLOYMENTS=(
    "app1 app1-instance app1-name 10 /api/v1/readiness 8080 2 30s"
    "app2 app2-instance app2-name 5 /ready 9090 3 20s"
    "app3 app3-instance app3-name 15 /status 8000 2 40s"
)

# **Step 1: Scale Deployments**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
    read -r DEPLOYMENT INSTANCE NAME EXPECTED_SIZE ENDPOINT PORT INCREMENT PAUSE <<< "$APP_DATA"
    scale_deployment "$DEPLOYMENT" "$INSTANCE" "$NAME" "$EXPECTED_SIZE" "$INCREMENT" "$PAUSE"
done

# **Step 2: Wait for Deployments to be Ready**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
    read -r DEPLOYMENT INSTANCE NAME EXPECTED_SIZE ENDPOINT PORT INCREMENT PAUSE <<< "$APP_DATA"
    wait_for_deployment_ready "$DEPLOYMENT"
done

# **Step 3: Poll Pods for Readiness**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
    read -r DEPLOYMENT INSTANCE NAME EXPECTED_SIZE ENDPOINT PORT INCREMENT PAUSE <<< "$APP_DATA"
    poll_pods_http "$DEPLOYMENT" "$INSTANCE" "$NAME" "$ENDPOINT" "$PORT" "$EXPECTED_SIZE"
done
