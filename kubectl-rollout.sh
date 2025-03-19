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

      # Perform HTTP request and capture both status code and response
      HTTP_RESPONSE=$(curl --write-out "%{http_code}" --silent --output /dev/null "$URL")
      
      if [[ "$HTTP_RESPONSE" -eq 200 ]]; then
        log "✅ Pod $POD_NAME ($POD_IP) is ready! (HTTP 200)"
      else
        log "❌ Pod $POD_NAME returned HTTP status: $HTTP_RESPONSE"
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
