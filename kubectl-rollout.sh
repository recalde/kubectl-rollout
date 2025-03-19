#!/bin/bash

set -e  ️# Exit on any error

# Record script start time
START_TIME=$(date +%s)

log() {
  local CURRENT_TIME=$(date +%s)
  local ELAPSED=$((CURRENT_TIME - START_TIME))
  local MINUTES=$((ELAPSED / 60))
  local SECONDS=$((ELAPSED % 60))
  printf "[%02d:%02d] %s\n" "$MINUTES" "$SECONDS" "$1"
}

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

wait_for_deployment_ready() {
  local DEPLOYMENT=$1
  log "Waiting for $DEPLOYMENT to be fully rolled out..."
  if ! kubectl rollout status deployment "$DEPLOYMENT" 2>/dev/null; then
    log "❌ ERROR: Deployment $DEPLOYMENT failed to become ready."
    return 1
  fi
  log "✅ Deployment $DEPLOYMENT is fully rolled out."
}

poll_pods_http() {
  local DEPLOYMENT=$1 SELECTOR=$2 TARGET_REPLICAS=$3 WAIT_BEFORE_POLL=$4 HTTP_PORT=$5 RETRY_DELAY=$6 MAX_RETRIES=$7

  log "⌛ Waiting $WAIT_BEFORE_POLL sec before polling pods for $DEPLOYMENT..."
  sleep "$WAIT_BEFORE_POLL"

  log "Polling pods for $DEPLOYMENT (Selector: '$SELECTOR') on port $HTTP_PORT..."

  declare -A POD_IP_MAP
  while IFS=' ' read -r POD_NAME POD_IP; do
    [[ -n "$POD_NAME" && -n "$POD_IP" ]] && POD_IP_MAP["$POD_NAME"]="$POD_IP"
  done < <(kubectl get pods -l "$SELECTOR" --field-selector=status.phase=Running -o=jsonpath="{range .items[*]}{.metadata.name} {.status.podIP}{'\n'}{end}" 2>/dev/null)

  if [[ ${#POD_IP_MAP[@]} -eq 0 ]]; then
    log "❌ ERROR: No running pods with valid IPs found for $DEPLOYMENT."
    return 1
  fi

  for (( RETRIES=0; RETRIES < MAX_RETRIES; RETRIES++ )); do
    local NEXT_ROUND=()
    for POD_NAME in "${!POD_IP_MAP[@]}"; do
      local POD_IP=${POD_IP_MAP[$POD_NAME]}
      local URL="http://${POD_IP}:${HTTP_PORT}${ENDPOINT}"
      log "Checking $URL for pod $POD_NAME..."

      RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" --max-time 10 "$URL")
      HTTP_STATUS=$(echo "$RESPONSE" | grep -o 'HTTPSTATUS:[0-9]*' | cut -d: -f2)
      BODY=$(echo "$RESPONSE" | sed -e "s/HTTPSTATUS:[0-9]*//")

      if [[ "$HTTP_STATUS" -eq 200 ]]; then
        if echo "$BODY" | grep -qE "$(echo "$VALIDATION_STRING" | sed 's/[]\/$*.^[]/\\&/g')"; then
          log "✅ Pod $POD_NAME ($POD_IP) is ready! (HTTP 200, Validation Matched)"
        else
          log "❌ Pod $POD_NAME ($POD_IP) failed validation. Expected: $VALIDATION_STRING"
          NEXT_ROUND+=("$POD_NAME")
        fi
      else
        log "❌ Pod $POD_NAME returned HTTP status: $HTTP_STATUS"
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
ENDPOINT="/api/v1/readiness"
VALIDATION_STRING='{"ClusterSize":4}'

DEPLOYMENT=("deploy1" "deploy2" "deploy3")
SELECTOR=("app=my-app,instance=instance1" "app=my-app,instance=instance2" "app=my-app,instance=instance3")
WAVES=("1" "1" "2")
TARGET_REPLICAS=(10 5 15)
SCALE_DELAY=(30 20 40)
SCALE_INCREMENT=(2 3 2)
WAIT_BEFORE_POLL=(15 20 30)
HTTP_PORT=(8080 9090 8000)
RETRY_DELAY=(10 15 20)
MAX_RETRIES=(5 6 7)

# Group deployments by wave
declare -A WAVE_GROUPS
for i in "${!DEPLOYMENT[@]}"; do
  WAVE_GROUPS["${WAVES[$i]}"]+="$i "
done

# Process each wave
for WAVE in $(printf "%s\n" "${!WAVE_GROUPS[@]}" | sort -n); do
  log "🚀 Starting WAVE $WAVE..."

  for i in ${WAVE_GROUPS[$WAVE]}; do
    scale_deployment "${DEPLOYMENT[$i]}" "${TARGET_REPLICAS[$i]}" "${SCALE_DELAY[$i]}" "${SCALE_INCREMENT[$i]}"
  done

  for i in ${WAVE_GROUPS[$WAVE]}; do
    wait_for_deployment_ready "${DEPLOYMENT[$i]}"
  done

  for i in ${WAVE_GROUPS[$WAVE]}; do
    poll_pods_http "${DEPLOYMENT[$i]}" "${SELECTOR[$i]}" "${TARGET_REPLICAS[$i]}" "${WAIT_BEFORE_POLL[$i]}" "${HTTP_PORT[$i]}" "${RETRY_DELAY[$i]}" "${MAX_RETRIES[$i]}"
  done

  log "✅ All deployments in WAVE $WAVE are fully ready!"
done

log "🎉 ✅ All waves completed successfully!"
