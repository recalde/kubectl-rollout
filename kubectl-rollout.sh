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
  local DEPLOYMENT_NAME=$1 INSTANCE=$2 NAME=$3 TARGET_REPLICAS=$4 ENDPOINT=$5 PORT=$6 INCREMENT=$7 PAUSE=$8 VALIDATION_STRING=$9
  local RETRY_INTERVAL=5 MAX_RETRIES=5

  log "Polling pods for $DEPLOYMENT_NAME (Validation: '$VALIDATION_STRING') on port $PORT..."

  # Strip surrounding single quotes if present
  VALIDATION_STRING=$(echo "$VALIDATION_STRING" | sed "s/^'//;s/'$//")

  # Fetch all pod names and IPs in a single kubectl call and store them in an associative array
  declare -A POD_IP_MAP
  while IFS=' ' read -r POD_NAME POD_IP; do
    [[ -n "$POD_NAME" && -n "$POD_IP" ]] && POD_IP_MAP["$POD_NAME"]="$POD_IP"
  done < <(kubectl get pods -l "app.kubernetes.io/instance=${INSTANCE},app.kubernetes.io/name=${NAME}" \
    --field-selector=status.phase=Running -o=jsonpath="{range .items[*]}{.metadata.name} {.status.podIP}{'\n'}{end}")

  if [[ ${#POD_IP_MAP[@]} -eq 0 ]]; then
    log "ERROR: No running pods with valid IPs found for $DEPLOYMENT_NAME."
    return 1
  fi

  for (( RETRIES=0; RETRIES < MAX_RETRIES; RETRIES++ )); do
    local NEXT_ROUND=()
    for POD_NAME in "${!POD_IP_MAP[@]}"; do
      local POD_IP=${POD_IP_MAP[$POD_NAME]}
      local URL="http://${POD_IP}:${PORT}${ENDPOINT}"
      log "Checking $URL for pod $POD_NAME..."
      
      RESPONSE=$(curl --max-time 10 -s "$URL" || echo "ERROR")

      # Fix: Use grep with escaped JSON pattern
      if echo "$RESPONSE" | grep -qE "$(echo "$VALIDATION_STRING" | sed 's/[]\/$*.^[]/\\&/g')"; then
        log "Pod $POD_NAME ($POD_IP) is ready!"
      else
        log "Validation failed for pod $POD_NAME. Expected pattern: $VALIDATION_STRING, but got: $RESPONSE"
        NEXT_ROUND+=("$POD_NAME")
      fi
    done

    if [[ ${#NEXT_ROUND[@]} -eq 0 ]]; then
      log "All pods in $DEPLOYMENT_NAME are confirmed ready."
      return 0
    fi

    log "Retrying ${#NEXT_ROUND[@]} failed pods in $RETRY_INTERVAL seconds..."
    sleep $RETRY_INTERVAL
  done

  log "WARNING: Some pods did not become ready: ${NEXT_ROUND[*]}"
}

# Define deployments (format: "DEPLOYMENT INSTANCE NAME TARGET_REPLICAS ENDPOINT PORT INCREMENT PAUSE VALIDATION_STRING")
DEPLOYMENTS=(
  "deploy1 app-instance deploy1 10 /api/v1/readiness 8080 2 30s '{\"ClusterSize\":4}'"
  "deploy2 app-instance deploy2 5 /ready 9090 3 20s '{\"ready\":true}'"
  "deploy3 app-instance deploy3 15 /status 8000 2 40s '{\"service-ok\":\"yes\"}'"
)

# **Step 1: Scale Deployments**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
  read -r DEPLOYMENT INSTANCE NAME TARGET_REPLICAS ENDPOINT PORT INCREMENT PAUSE VALIDATION_STRING <<< "$APP_DATA"
  scale_deployment "$DEPLOYMENT" "$INSTANCE" "$NAME" "$TARGET_REPLICAS" "$INCREMENT" "$PAUSE"
done

# **Step 2: Wait for Deployments to be Ready**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
  read -r DEPLOYMENT INSTANCE NAME TARGET_REPLICAS ENDPOINT PORT INCREMENT PAUSE VALIDATION_STRING <<< "$APP_DATA"
  wait_for_deployment_ready "$DEPLOYMENT"
done

# **Step 3: Poll Pods for Readiness**
for APP_DATA in "${DEPLOYMENTS[@]}"; do
  read -r DEPLOYMENT INSTANCE NAME TARGET_REPLICAS ENDPOINT PORT INCREMENT PAUSE VALIDATION_STRING <<< "$APP_DATA"
  poll_pods_http "$DEPLOYMENT" "$INSTANCE" "$NAME" "$TARGET_REPLICAS" "$ENDPOINT" "$PORT" "$INCREMENT" "$PAUSE" "$VALIDATION_STRING"
done
