#!/bin/bash

set -e  # Exit on any error

# Ensure required environment variables are set
if [[ -z "$DEPLOYMENT_NAME" || -z "$ROLLOUT_REPLICA_COUNT" || -z "$ROLLOUT_INCREMENT" || -z "$ROLLOUT_PAUSE" ]]; then
    echo "$(date +'%H:%M:%S') ERROR: Missing required environment variables."
    echo "Ensure DEPLOYMENT_NAME, ROLLOUT_REPLICA_COUNT, ROLLOUT_INCREMENT, and ROLLOUT_PAUSE are set."
    exit 1
fi

# Get the current replica count
CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT_NAME" -o=jsonpath='{.spec.replicas}')

if [[ -z "$CURRENT_REPLICAS" ]]; then
    echo "$(date +'%H:%M:%S') ERROR: Could not retrieve current replica count. Check if the deployment exists."
    exit 1
fi

echo "$(date +'%H:%M:%S') Starting rollout for deployment: $DEPLOYMENT_NAME"
echo "$(date +'%H:%M:%S') Current replicas: $CURRENT_REPLICAS"
echo "$(date +'%H:%M:%S') Target replicas: $ROLLOUT_REPLICA_COUNT"
echo "$(date +'%H:%M:%S') Increment: $ROLLOUT_INCREMENT"
echo "$(date +'%H:%M:%S') Pause between increments: $ROLLOUT_PAUSE"

# Incrementally scale up
while [[ "$CURRENT_REPLICAS" -lt "$ROLLOUT_REPLICA_COUNT" ]]; do
    # Determine next scale value
    NEW_REPLICAS=$((CURRENT_REPLICAS + ROLLOUT_INCREMENT))

    # Ensure we do not exceed the target count
    if [[ "$NEW_REPLICAS" -gt "$ROLLOUT_REPLICA_COUNT" ]]; then
        NEW_REPLICAS="$ROLLOUT_REPLICA_COUNT"
    fi

    echo "$(date +'%H:%M:%S') Scaling deployment $DEPLOYMENT_NAME to $NEW_REPLICAS replicas..."
    kubectl scale deployment "$DEPLOYMENT_NAME" --replicas="$NEW_REPLICAS"

    # Wait for rollout pause
    echo "$(date +'%H:%M:%S') Waiting for $ROLLOUT_PAUSE before next increment..."
    sleep "$ROLLOUT_PAUSE"

    # Update current replica count
    CURRENT_REPLICAS="$NEW_REPLICAS"
done

echo "$(date +'%H:%M:%S') Final replica count reached. Waiting for all pods to be in a healthy state..."

# Wait until all replicas are ready
kubectl rollout status deployment "$DEPLOYMENT_NAME"

echo "$(date +'%H:%M:%S') Deployment rollout complete."
