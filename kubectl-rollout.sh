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
  local INSTANCE=$1 DEPLOYMENT=$2 SELECTOR=$3 TARGET_REPLICAS=$4 SCALING_DELAY=$5 SCALING_INCREMENT=$6
  log "Starting rollout for $DEPLOYMENT (Target: $TARGET_REPLICAS, Increment: $SCALING_INCREMENT, Pause: $SCALING_DELAY)"

  local CURRENT_REPLICAS
  CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -o=jsonpath='{.spec.replicas}' 2>/dev/null) || {
    log "❌ ERROR: Failed to get replica count for $DEPLOYMENT"
    return 1
  }

  while (( CURRENT_REPLICAS < TARGET_REPLICAS )); do
    local NEW_REPLICAS=$(( CURRENT_REPLICAS + SCALING_INCREMENT > TARGET_REPLICAS ? TARGET_REPLICAS : CURRENT_REPLICAS + SCALING_INCREMENT ))
    log "Scaling $DEPLOYMENT to $NEW_REPLICAS replicas..."
    if ! kubectl scale deployment "$DEPLOYMENT" --replicas="$NEW_REPLICAS" 2>/dev/null; then
      log "❌ ERROR: Failed to scale $DEPLOYMENT to $NEW_REPLICAS replicas"
      return 1
    fi

    if (( NEW_REPLICAS < TARGET_REPLICAS )); then
      log "Waiting $SCALING_DELAY before next increment..."
      sleep "${SCALING_DELAY%s}"
    fi

    CURRENT_REPLICAS=$NEW_REPLICAS
  done

  log "✅ Scaling complete for $DEPLOYMENT."
}

wait_for_deployment_ready() {
  log "Waiting for $1 to be fully rolled out..."
  if ! kubectl rollout status deployment "$1" 2>/dev/null; then
    log "❌ ERROR: Deployment $1 failed to become ready."
    return 1
  fi
  log "✅ Deployment $1 is fully rolled out."
}

poll_pods_http() {
  local INSTANCE=$1 DEPLOYMENT=$2 SELECTOR=$3 TARGET_REPLICAS=$4 WAIT_BEFORE_POLL=$5 HTTP_ENDPOINT=$6 HTTP_PORT=$7 VALIDATION_STRING=$8 RETRY_DELAY=$9 MAX_RETRIES=${10}
  
  log "⌛ Waiting $WAIT_BEFORE_POLL before polling pods for $DEPLOYMENT..."
  sleep "${WAIT_BEFORE_POLL%s}"

  log "Polling pods for $DEPLOYMENT (Validation: '$VALIDATION_STRING') on port $HTTP_PORT..."

  VALIDATION_STRING=$(echo "$VALIDATION_STRING" | sed "s/^'//;s/'$//")  # Strip surrounding single quotes

  declare -A POD_IP_MAP
  while IFS=' ' read -r POD_NAME POD_IP; do
    [[ -n "$POD_NAME" && -n "$POD_IP" ]] && POD_IP_MAP["$POD_NAME"]="$POD_IP"
  done < <(kubectl get pods -l "app.kubernetes.io/instance=${INSTANCE},app.kubernetes.io/name=${SELECTOR}" \
    --field-selector=status.phase=Running -o=jsonpath="{range .items[*]}{.metadata.name} {.status.podIP}{'\n'}{end}" 2>/dev/null)

  if [[ ${#POD_IP_MAP[@]} -eq 0 ]]; then
    log "❌ ERROR: No running pods with valid IPs found for $DEPLOYMENT."
    return 1
  fi

  for (( RETRIES=0; RETRIES < MAX_RETRIES; RETRIES++ )); do
    local NEXT_ROUND=()
    for POD_NAME in "${!POD_IP_MAP[@]}"; do
      local POD_IP=${POD_IP_MAP[$POD_NAME]}
      local URL="http://${POD_IP}:${HTTP_PORT}${HTTP_ENDPOINT}"
      log "Checking $URL for pod $POD_NAME..."
      
      RESPONSE=$(curl --max-time 10 -s "$URL" || echo "ERROR")

      if echo "$RESPONSE" | grep -qE "$(echo "$VALIDATION_STRING" | sed 's/[]\/$*.^[]/\\&/g')"; then
        log "✅ Pod $POD_NAME ($POD_IP) is ready!"
      else
        log "❌ Validation failed for pod $POD_NAME. Expected: $VALIDATION_STRING, but got: $RESPONSE"
        NEXT_ROUND+=("$POD_NAME")
      fi
    done

    if [[ ${#NEXT_ROUND[@]} -eq 0 ]]; then
      log "✅ All pods in $DEPLOYMENT are confirmed ready."
      return 0
    fi

    log "🔄 Retrying ${#NEXT_ROUND[@]} failed pods in $RETRY_DELAY..."
    sleep "${RETRY_DELAY%s}"
  done

  log "⚠️ WARNING: Some pods did not become ready: ${NEXT_ROUND[*]}"
}

### **🚀 Execute Deployment in Waves**
CURRENT_WAVE=""
WAVE_DEPLOYMENTS=()
WAVE_PROCESSES=()

for APP_DATA in "${DEPLOYMENTS[@]}"; do
  read -r WAVE INSTANCE DEPLOYMENT SELECTOR TARGET_REPLICAS SCALING_DELAY SCALING_INCREMENT WAIT_BEFORE_POLL HTTP_ENDPOINT HTTP_PORT VALIDATION_STRING RETRY_DELAY MAX_RETRIES <<< "$APP_DATA"

  if [[ "$CURRENT_WAVE" != "$WAVE" ]]; then
    if [[ -n "$CURRENT_WAVE" && ${#WAVE_PROCESSES[@]} -gt 0 ]]; then
      log "⌛ Waiting for all deployments in Wave $CURRENT_WAVE to finish..."
      wait "${WAVE_PROCESSES[@]}"
      log "✅ All deployments in Wave $CURRENT_WAVE are fully ready!"
      WAVE_PROCESSES=()
    fi

    CURRENT_WAVE="$WAVE"
    log "🚀 Starting WAVE $CURRENT_WAVE..."
  fi

  (
    scale_deployment "$INSTANCE" "$DEPLOYMENT" "$SELECTOR" "$TARGET_REPLICAS" "$SCALING_DELAY" "$SCALING_INCREMENT"
    wait_for_deployment_ready "$DEPLOYMENT"
  ) &

  WAVE_PROCESSES+=($!)
  WAVE_DEPLOYMENTS+=("$APP_DATA")
done

if [[ ${#WAVE_PROCESSES[@]} -gt 0 ]]; then
  log "⌛ Waiting for all deployments in Wave $CURRENT_WAVE to finish..."
  wait "${WAVE_PROCESSES[@]}"
  log "✅ All deployments in Wave $CURRENT_WAVE are fully ready!"
fi

# Now, start polling for readiness after all deployments in the wave are fully ready
for APP_DATA in "${WAVE_DEPLOYMENTS[@]}"; do
  read -r _ INSTANCE DEPLOYMENT SELECTOR TARGET_REPLICAS _ _ WAIT_BEFORE_POLL HTTP_ENDPOINT HTTP_PORT VALIDATION_STRING RETRY_DELAY MAX_RETRIES <<< "$APP_DATA"
  poll_pods_http "$INSTANCE" "$DEPLOYMENT" "$SELECTOR" "$TARGET_REPLICAS" "$WAIT_BEFORE_POLL" "$HTTP_ENDPOINT" "$HTTP_PORT" "$VALIDATION_STRING" "$RETRY_DELAY" "$MAX_RETRIES"
done

log "✅ All waves completed successfully!"
