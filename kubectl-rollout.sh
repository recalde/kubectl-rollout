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
  local INSTANCE=$1 DEPLOYMENT=$2 SELECTOR=$3 TARGET_REPLICAS=$4 SCALE_DELAY=$5 SCALE_INCREMENT=$6
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
  
  log "⌛ Waiting $WAIT_BEFORE_POLL sec before polling pods for $DEPLOYMENT..."
  sleep "$WAIT_BEFORE_POLL"

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

    log "🔄 Retrying ${#NEXT_ROUND[@]} failed pods in $RETRY_DELAY sec..."
    sleep "$RETRY_DELAY"
  done

  log "⚠️ WARNING: Some pods did not become ready: ${NEXT_ROUND[*]}"
}

### **🛠 Deployment Configuration**
# Base Configuration (All values in **seconds**)
APP_INSTANCE="app-instance"
DEPLOYMENT_NAMES=("deploy1" "deploy2" "deploy3")
DEPLOYMENT_SELECTORS=("deploy1" "deploy2" "deploy3")
DESIRED_REPLICAS=(10 5 15)
SCALE_DELAY=(30 20 40)
SCALE_INCREMENT=(2 3 2)
WAIT_BEFORE_POLL=(15 20 30)
HTTP_ENDPOINT="/api/v1/readiness"
HTTP_PORT=(8080 9090 8000)
VALIDATION_STRING='{"ClusterSize":4}'
RETRY_DELAY=(10 15 20)
MAX_RETRIES=(5 6 7)

# Define deployment waves
DEPLOYMENTS=(
  "1 $APP_INSTANCE ${DEPLOYMENT_NAMES[0]} ${DEPLOYMENT_SELECTORS[0]} ${DESIRED_REPLICAS[0]} ${SCALE_DELAY[0]} ${SCALE_INCREMENT[0]} ${WAIT_BEFORE_POLL[0]} $HTTP_ENDPOINT ${HTTP_PORT[0]} '$VALIDATION_STRING' ${RETRY_DELAY[0]} ${MAX_RETRIES[0]}"
  "1 $APP_INSTANCE ${DEPLOYMENT_NAMES[1]} ${DEPLOYMENT_SELECTORS[1]} ${DESIRED_REPLICAS[1]} ${SCALE_DELAY[1]} ${SCALE_INCREMENT[1]} ${WAIT_BEFORE_POLL[1]} $HTTP_ENDPOINT ${HTTP_PORT[1]} '$VALIDATION_STRING' ${RETRY_DELAY[1]} ${MAX_RETRIES[1]}"
  "2 $APP_INSTANCE ${DEPLOYMENT_NAMES[2]} ${DEPLOYMENT_SELECTORS[2]} ${DESIRED_REPLICAS[2]} ${SCALE_DELAY[2]} ${SCALE_INCREMENT[2]} ${WAIT_BEFORE_POLL[2]} $HTTP_ENDPOINT ${HTTP_PORT[2]} '$VALIDATION_STRING' ${RETRY_DELAY[2]} ${MAX_RETRIES[2]}"
)

### **🚀 Execute Deployment in Waves**
for WAVE in $(cut -d ' ' -f 1 <<< "${DEPLOYMENTS[@]}" | sort -u); do
  WAVE_DEPLOYMENTS=($(grep "^$WAVE " <<< "${DEPLOYMENTS[@]}"))

  log "🚀 Starting WAVE $WAVE..."

  for APP_DATA in "${WAVE_DEPLOYMENTS[@]}"; do
    poll_pods_http "$APP_DATA"
  done

  log "✅ All deployments in WAVE $WAVE are fully ready!"
done

log "🎉 ✅ All waves completed successfully!"
