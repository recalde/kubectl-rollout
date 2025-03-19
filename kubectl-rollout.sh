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

# Scale a Kubernetes deployment incrementally
scale_deployment() {
  local DEPLOYMENT=$1 TARGET_REPLICAS=$2 SCALE_DELAY=$3 SCALE_INCREMENT=$4
  log "Starting rollout for $DEPLOYMENT (Target: $TARGET_REPLICAS, Increment: $SCALE_INCREMENT, Pause: $SCALE_DELAY sec)"

  local CURRENT_REPLICAS
  CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -o=jsonpath='{.spec.replicas}' 2>/dev/null) || {
    log "❌ ERROR: Failed to get replica count for $DEPLOYMENT"
    return 1
  }

  while (( CURRENT_REPLICAS < TARGET_REPLICAS )); do
    local NEW_REPLICAS=$(( CURRENT_REPLICAS + SCALE_INCREMENT > TARGET_REPLICAS ? TARGET_REPLICAS : CURRENT_REPLICAS + SCALE_INCREMENT ))
    log "Scaling $DEPLOYMENT to $NEW_REPLICAS replicas..."
    if ! kubectl scale deployment "$DEPLOYMENT" --replicas="$NEW_REPLICAS" 2>/dev/null; then
      log "❌ ERROR: Failed to scale $DEPLOYMENT to $NEW_REPLICAS replicas"
      return 1
    fi

    if (( NEW_REPLICAS < TARGET_REPLICAS )); then
      log "Waiting $SCALE_DELAY sec before next increment..."
      sleep "$SCALE_DELAY"
    fi

    CURRENT_REPLICAS=$NEW_REPLICAS
  done

  log "✅ Scaling complete for $DEPLOYMENT."
}

# Wait for a deployment to be fully ready
wait_for_deployment_ready() {
  local DEPLOYMENT=$1
  log "Waiting for $DEPLOYMENT to be fully rolled out..."
  if ! kubectl rollout status deployment "$DEPLOYMENT" 2>/dev/null; then
    log "❌ ERROR: Deployment $DEPLOYMENT failed to become ready."
    return 1
  fi
  log "✅ Deployment $DEPLOYMENT is fully rolled out."
}

# Poll pods for HTTP readiness
poll_pods_http() {
  local DEPLOYMENT=$1 SELECTOR=$2 TARGET_REPLICAS=$3 WAIT_BEFORE_POLL=$4 HTTP_ENDPOINT=$5 HTTP_PORT=$6 VALIDATION_STRING=$7 RETRY_DELAY=$8 MAX_RETRIES=$9

  log "⌛ Waiting $WAIT_BEFORE_POLL sec before polling pods for $DEPLOYMENT..."
  sleep "$WAIT_BEFORE_POLL"

  log "Polling pods for $DEPLOYMENT (Validation: '$VALIDATION_STRING') on port $HTTP_PORT..."

  declare -A POD_IP_MAP
  while IFS=' ' read -r POD_NAME POD_IP; do
    [[ -n "$POD_NAME" && -n "$POD_IP" ]] && POD_IP_MAP["$POD_NAME"]="$POD_IP"
  done < <(kubectl get pods -l "app.kubernetes.io/name=${SELECTOR}" \
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

    log "🔄 Retrying ${#NEXT_ROUND[@]} failed pods in $RETRY_DELAY sec..."
    sleep "$RETRY_DELAY"
  done

  log "⚠️ WARNING: Some pods did not become ready: ${NEXT_ROUND[*]}"
}

### **🛠 Deployment Configuration**
DEPLOYMENTS=(
  # WAVE  DEPLOYMENT  SELECTOR  TARGET_REPLICAS  SCALE_DELAY  SCALE_INCREMENT  WAIT_BEFORE_POLL  HTTP_ENDPOINT        HTTP_PORT  VALIDATION_STRING       RETRY_DELAY  MAX_RETRIES
  "1      deploy1     deploy1   10              30           2                15                /api/v1/readiness    8080       '{\"ClusterSize\":4}'   10          5"
  "1      deploy2     deploy2   5               20           3                20                /api/v1/readiness    9090       '{\"ClusterSize\":4}'   15          6"
  "2      deploy3     deploy3   15              40           2                30                /api/v1/readiness    8000       '{\"ClusterSize\":4}'   20          7"
)

### **🚀 Execute Deployment in Waves**
for WAVE in $(awk '{print $1}' <<< "${DEPLOYMENTS[@]}" | sort -u); do
  WAVE_DEPLOYMENTS=($(grep "^$WAVE " <<< "${DEPLOYMENTS[@]}"))

  log "🚀 Starting WAVE $WAVE..."

  # First, scale all deployments in the wave
  for APP_DATA in "${WAVE_DEPLOYMENTS[@]}"; do
    scale_deployment $(awk '{print $2, $4, $5, $6}' <<< "$APP_DATA")
  done

  # Wait for all deployments in the wave to be ready
  for APP_DATA in "${WAVE_DEPLOYMENTS[@]}"; do
    wait_for_deployment_ready $(awk '{print $2}' <<< "$APP_DATA")
  done

  # Poll all deployments in the wave for readiness
  for APP_DATA in "${WAVE_DEPLOYMENTS[@]}"; do
    poll_pods_http $(awk '{print $2, $3, $4, $7, $8, $9, $10, $11, $12}' <<< "$APP_DATA")
  done

  log "✅ All deployments in WAVE $WAVE are fully ready!"
done

log "🎉 ✅ All waves completed successfully!"
