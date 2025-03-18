#!/bin/bash

set -e  # Exit on any error

# Function to perform incremental rollout for a deployment
scale_deployment() {
    local DEPLOYMENT_NAME=$1
    local TARGET_REPLICAS=$2
    local INCREMENT=$3
    local PAUSE=$4

    echo "$(date +'%H:%M:%S') Starting rollout for deployment: $DEPLOYMENT_NAME"

    # Get the current replica count
    CURRENT_REPLICAS=$(kubectl get deployment "$DEPLOYMENT_NAME" -o=jsonpath='{.spec.replicas}')
    
    if [[ -z "$CURRENT_REPLICAS" ]]; then
        echo "$(date +'%H:%M:%S') ERROR: Could not retrieve current replica count for $DEPLOYMENT_NAME. Skipping..."
        return 1
    fi

    echo "$(date +'%H:%M:%S') Current replicas: $CURRENT_REPLICAS"
    echo "$(date +'%H:%M:%S') Target replicas: $TARGET_REPLICAS"
    echo "$(date +'%H:%M:%S') Increment: $INCREMENT"
    echo "$(date +'%H:%M:%S') Pause between increments: $PAUSE"

    # Incrementally scale up
    while [[ "$CURRENT_REPLICAS" -lt "$TARGET_REPLICAS" ]]; do
        # Determine next scale value
        NEW_REPLICAS=$((CURRENT_REPLICAS + INCREMENT))

        # Ensure we do not exceed the target count
        if [[ "$NEW_REPLICAS" -gt "$TARGET_REPLICAS" ]]; then
            NEW_REPLICAS="$TARGET_REPLICAS"
        fi

        echo "$(date +'%H:%M:%S') Scaling deployment $DEPLOYMENT_NAME to $NEW_REPLICAS replicas..."
        kubectl scale deployment "$DEPLOYMENT_NAME" --replicas="$NEW_REPLICAS"

        # Wait for rollout pause
        echo "$(date +'%H:%M:%S') Waiting for $PAUSE before next increment..."
        sleep "$PAUSE"

        # Update current replica count
        CURRENT_REPLICAS="$NEW_REPLICAS"
    done

    echo "$(date +'%H:%M:%S') Final replica count reached for $DEPLOYMENT_NAME. Waiting for all pods to be in a healthy state..."
    
    # Wait until all replicas are ready
    kubectl rollout status deployment "$DEPLOYMENT_NAME"

    echo "$(date +'%H:%M:%S') Deployment rollout complete for $DEPLOYMENT_NAME."
}

# Define rollout parameters
ROLLOUT_REPLICA_COUNT=10
ROLLOUT_INCREMENT=2
ROLLOUT_PAUSE=30s

# Call the function for each deployment separately
scale_deployment "app1" "$ROLLOUT_REPLICA_COUNT" "$ROLLOUT_INCREMENT" "$ROLLOUT_PAUSE"
scale_deployment "app2" "$ROLLOUT_REPLICA_COUNT" "$ROLLOUT_INCREMENT" "$ROLLOUT_PAUSE"
scale_deployment "app3" "$ROLLOUT_REPLICA_COUNT" "$ROLLOUT_INCREMENT" "$ROLLOUT_PAUSE"
