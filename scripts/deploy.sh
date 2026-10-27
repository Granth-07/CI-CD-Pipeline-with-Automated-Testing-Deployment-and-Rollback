#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

IMAGE="${1:-}"
if [ -z "$IMAGE" ]; then
    echo "Usage: $0 <image:tag>"
    exit 1
fi

TAG_FILE="${TAG_FILE:-/opt/app/previous_tag}"
CONTAINER_NAME="${CONTAINER_NAME:-rag-api}"
PORT="${PORT:-8000}"
DATA_VOLUME="${DATA_VOLUME:-/data}"
HEALTH_HOST="${HEALTH_HOST:-localhost}"
HEALTH_URL="${HEALTH_URL:-http://${HEALTH_HOST}:${PORT}/health}"
SKIP_PULL="${SKIP_PULL:-false}"

PREVIOUS_TAG=""
if [ -f "$TAG_FILE" ]; then
    PREVIOUS_TAG="$(cat "$TAG_FILE")"
fi

echo "Deploying image: $IMAGE (Previous: ${PREVIOUS_TAG:-none})"

if [ "$SKIP_PULL" != "true" ]; then
    echo "Pulling image $IMAGE..."
    docker pull "$IMAGE"
fi

echo "Stopping existing container if present..."
docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "Starting container $CONTAINER_NAME..."
# Note: $IMAGE can carry extra env if provided via EXTRA_DOCKER_ARGS
docker run -d --name "$CONTAINER_NAME" -p "${PORT}:8000" -v "${DATA_VOLUME}:/data" ${EXTRA_DOCKER_ARGS:-} "$IMAGE"

echo "Performing health check: $HEALTH_URL (5 retries, 3s apart)..."
HEALTHY=false
for i in 1 2 3 4 5; do
    sleep 3
    if curl -f -s "$HEALTH_URL" >/dev/null 2>&1; then
        HEALTHY=true
        echo "Health check passed on attempt $i"
        break
    else
        echo "Health check attempt $i failed..."
    fi
done

if [ "$HEALTHY" = true ]; then
    mkdir -p "$(dirname "$TAG_FILE")"
    echo "$IMAGE" > "$TAG_FILE"
    echo "DEPLOY SUCCESS: $IMAGE is live and healthy."
    exit 0
else
    echo "DEPLOY FAILED: Health check failed for $IMAGE"
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    if [ -n "$PREVIOUS_TAG" ]; then
        echo "Restarting previous image: $PREVIOUS_TAG"
        docker run -d --name "$CONTAINER_NAME" -p "${PORT}:8000" -v "${DATA_VOLUME}:/data" "$PREVIOUS_TAG"
        echo "ROLLBACK"
        exit 1
    else
        echo "ROLLBACK FAILED: no previous version"
        exit 1
    fi
fi
