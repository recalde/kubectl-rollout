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
  CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT_NAME" -o=jsonpath='{.spec.replicas}' 2>/dev/null) || {
    log "❌ ERROR: Failed to get replica count for $DEPLOYMENT_NAME"
    return 1
  }

  while (( CURRENT_REPLICAS < TARGET_REPLICAS )); do
    local NEW_REPLICAS=$(( CURRENT_REPLICAS + INCREMENT > TARGET_REPLICAS ? TARGET_REPLICAS : CURRENT_REPLICAS + INCREMENT ))
    log "Scaling $DEPLOYMENT_NAME to $NEW_REPLICAS replicas..."
    if ! kubectl scale deployment "$DEPLOYMENT_NAME" --replicas="$NEW_REPLICAS" 2>/dev/null; then
      log "❌ ERROR: Failed to scale $DEPLOYMENT_NAME to $NEW_REPLICAS replicas"
      return 1
    fi

    if (( NEW_REPLICAS < TARGET_REPLICAS )); then
      log "Waiting $PAUSE before next increment..."
      sleep "${PAUSE%s}"
    fi

    CURRENT_REPLICAS=$NEW_REPLICAS
  done

  log "✅ Scaling complete for $DEPLOYMENT_NAME."
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
  local DEPLOYMENT_NAME=$1 INSTANCE=$2 NAME=$3 TARGET_REPLICAS=$4 ENDPOINT=$5 PORT=$6 INCREMENT=$7 PAUSE=$8 VALIDATION_STRING=$9 WAIT_BEFORE_POLL=${10} RETRY_DELAY=${11} MAX_RETRIES=${12}
  
  log "⌛ Waiting $WAIT_BEFORE_POLL before polling pods for $DEPLOYMENT_NAME..."
  sleep "${WAIT_BEFORE_POLL%s}"

  log "Polling pods for $DEPLOYMENT_NAME (Validation: '$VALIDATION_STRING') on port $PORT..."

  # Strip surrounding single quotes if present
  VALIDATION_STRING=$(echo "$VALIDATION_STRING" | sed "s/^'//;s/'$//")

  # Fetch all pod names and IPs in a single kubectl call
  declare -A POD_IP_MAP
  while IFS=' ' read -r POD_NAME POD_IP; do
    [[ -n "$POD_NAME" && -n "$POD_IP" ]] && POD_IP_MAP["$POD_NAME"]="$POD_IP"
  done < <(kubectl get pods -l "app.kubernetes.io/instance=${INSTANCE},app.kubernetes.io/name=${NAME}" \
    --field-selector=status.phase=Running -o=jsonpath="{range .items[*]}{.metadata.name} {.status.podIP}{'\n'}{end}" 2>/dev/null)

  if [[ ${#POD_IP_MAP[@]} -eq 0 ]]; then
    log "❌ ERROR: No running pods with valid IPs found for $DEPLOYMENT_NAME."
    return 1
  fi

  for (( RETRIES=0; RETRIES < MAX_RETRIES; RETRIES++ )); do
    local NEXT_ROUND=()
    for POD_NAME in "${!POD_IP_MAP[@]}"; do
      local POD_IP=${POD_IP_MAP[$POD_NAME]}
      local URL="http://${POD_IP}:${PORT}${ENDPOINT}"
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
      log "✅ All pods in $DEPLOYMENT_NAME are confirmed ready."
      return 0
    fi

    log "🔄 Retrying ${#NEXT_ROUND[@]} failed pods in $RETRY_DELAY..."
    sleep "${RETRY_DELAY%s}"
  done

  log "⚠️ WARNING: Some pods did not become ready: ${NEXT_ROUND[*]}"
}

### **🛠 Deployment Configuration**
APP_INSTANCE="app-instance"
DEPLOYMENT_NAMES=("deploy1" "deploy2" "deploy3")
DEPLOYMENT_SELECTORS=("deploy1" "deploy2" "deploy3")
HTTP_ENDPOINT="/api/v1/readiness"
VALIDATION_STRING='{"ClusterSize":4}'
DESIRED_REPLICAS=(10 5 15)
PORT=(8080 9090 8000)
DELAY=("30s" "20s" "40s")
WAIT_BEFORE_POLL=("15s" "20s" "30s")  # New: Wait time before polling
RETRY_DELAY=("10s" "15s" "20s")       # New: Delay between retries
MAX_RETRIES=(5 6 7)                   # New: Max retry attempts

DEPLOYMENTS=(
  "1 ${DEPLOYMENT_NAMES[0]} $APP_INSTANCE ${DEPLOYMENT_SELECTORS[0]} ${DESIRED_REPLICAS[0]} $HTTP_ENDPOINT ${PORT[0]} 2 ${DELAY[0]} '$VALIDATION_STRING' ${WAIT_BEFORE_POLL[0]} ${RETRY_DELAY[0]} ${MAX_RETRIES[0]}"
  "1 ${DEPLOYMENT_NAMES[1]} $APP_INSTANCE ${DEPLOYMENT_SELECTORS[1]} ${DESIRED_REPLICAS[1]} $HTTP_ENDPOINT ${PORT[1]} 3 ${DELAY[1]} '$VALIDATION_STRING' ${WAIT_BEFORE_POLL[1]} ${RETRY_DELAY[1]} ${MAX_RETRIES[1]}"
  "2 ${DEPLOYMENT_NAMES[2]} $APP_INSTANCE ${DEPLOYMENT_SELECTORS[2]} ${DESIRED_REPLICAS[2]} $HTTP_ENDPOINT ${PORT[2]} 2 ${DELAY[2]} '$VALIDATION_STRING' ${WAIT_BEFORE_POLL[2]} ${RETRY_DELAY[2]} ${MAX_RETRIES[2]}"
)

### **🚀 Execute Deployment in Waves**
CURRENT_WAVE=""
WAVE_PROCESSES=()

for APP_DATA in "${DEPLOYMENTS[@]}"; do
  read -r WAVE DEPLOYMENT INSTANCE NAME TARGET_REPLICAS ENDPOINT PORT INCREMENT PAUSE VALIDATION_STRING WAIT_BEFORE_POLL RETRY_DELAY MAX_RETRIES <<< "$APP_DATA"

  if [[ "$CURRENT_WAVE" != "$WAVE" ]]; then
    if [[ -n "$CURRENT_WAVE" && ${#WAVE_PROCESSES[@]} -gt 0 ]]; then
      log "⌛ Waiting for all deployments in Wave $CURRENT_WAVE to finish..."
      wait "${WAVE_PROCESSES[@]}"
      log "✅ All deployments in Wave $CURRENT_WAVE completed!"
      WAVE_PROCESSES=()
    fi

    CURRENT_WAVE="$WAVE"
    log "🚀 Starting WAVE $CURRENT_WAVE..."
  fi

  (
    scale_deployment "$DEPLOYMENT" "$INSTANCE" "$NAME" "$TARGET_REPLICAS" "$INCREMENT" "$PAUSE"
    wait_for_deployment_ready "$DEPLOYMENT"
    poll_pods_http "$DEPLOYMENT" "$INSTANCE" "$NAME" "$TARGET_REPLICAS" "$ENDPOINT" "$PORT" "$INCREMENT" "$PAUSE" "$VALIDATION_STRING" "$WAIT_BEFORE_POLL" "$RETRY_DELAY" "$MAX_RETRIES"
  ) &

  WAVE_PROCESSES+=($!)
done

wait "${WAVE_PROCESSES[@]}"
log "✅ All waves completed successfully!"
