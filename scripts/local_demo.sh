#!/usr/bin/env bash
set -uo pipefail
export MSYS_NO_PATHCONV=1

DEMO_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'rag_demo')"
DEMO_DATA="${DEMO_DIR}/data"
mkdir -p "${DEMO_DIR}" "${DEMO_DATA}"

export TAG_FILE="${DEMO_DIR}/previous_tag"
export CONTAINER_NAME="rag-api-demo"
export PORT="8000"
export DATA_VOLUME="rag_demo_data"
export SKIP_PULL="true"

cleanup() {
    echo "Cleaning up demo resources..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    rm -rf "$DEMO_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=================================================="
echo " Starting Local CI/CD & Rollback Demonstration    "
echo "=================================================="

# Stage 1: Build v1 Image
echo "[Stage 1] Building initial healthy release (rag-api:v1)..."
if docker build -t rag-api:v1 . ; then
    echo "[PASS] Stage 1: v1 built successfully"
else
    echo "[FAIL] Stage 1: v1 build failed"
    exit 1
fi

# Extra Stage: First-deploy failure (no previous version)
echo "[Extra Stage] Testing first-deploy failure handling..."
FD_OUT=$(EXTRA_DOCKER_ARGS="-e SIMULATE_FAILURE=true" bash scripts/deploy.sh rag-api:v1 2>&1 || true)
if echo "$FD_OUT" | grep -q "ROLLBACK FAILED: no previous version"; then
    echo "[PASS] Extra Stage: First-deploy failure handled properly"
else
    echo "[FAIL] Extra Stage: First-deploy failure not handled"; exit 1
fi

# Stage 2: Deploy v1
echo "[Stage 2] Deploying rag-api:v1 via scripts/deploy.sh..."
if bash scripts/deploy.sh rag-api:v1 ; then
    # Verify health endpoint returns 200
    if curl -f -s "http://localhost:${PORT}/health" | grep -q '"status":"ok"'; then
        echo "[PASS] Stage 2: v1 deployed and verified healthy"
    else
        echo "[FAIL] Stage 2: v1 health verification failed"
        exit 1
    fi
else
    echo "[FAIL] Stage 2: v1 deployment failed"
    exit 1
fi

# Stage 3: Build v2 with SIMULATE_FAILURE baked in
echo "[Stage 3] Building faulty release (rag-api:v2 with SIMULATE_FAILURE=true)..."
if printf "FROM rag-api:v1\nENV SIMULATE_FAILURE=true\n" | docker build -t rag-api:v2 - ; then
    echo "[PASS] Stage 3: v2 built successfully"
else
    echo "[FAIL] Stage 3: v2 build failed"
    exit 1
fi

# Stage 4: Deploy v2 (Expect failure and automated rollback to v1)
echo "[Stage 4] Deploying rag-api:v2 (Expecting failure and automatic rollback)..."
DEPLOY_OUTPUT=""
if DEPLOY_OUTPUT=$(bash scripts/deploy.sh rag-api:v2 2>&1); then
    echo "$DEPLOY_OUTPUT"
    echo "[FAIL] Stage 4: deploy.sh should have failed for faulty v2"
    exit 1
else
    echo "$DEPLOY_OUTPUT"
    if echo "$DEPLOY_OUTPUT" | grep -q "ROLLBACK"; then
        echo "[PASS] Stage 4: Faulty release failed healthcheck and triggered ROLLBACK"
    else
        echo "[FAIL] Stage 4: Rollback signal not detected"
        exit 1
    fi
fi

# Stage 5: Confirm v1 is restored and serving traffic
echo "[Stage 5] Confirming v1 is serving traffic after rollback..."
sleep 2
HEALTH_RESP=$(curl -s "http://localhost:${PORT}/health" || true)
if echo "$HEALTH_RESP" | grep -q '"status":"ok"'; then
    echo "Response: $HEALTH_RESP"
    echo "[PASS] Stage 5: Service restored to healthy v1 release"
else
    echo "Response: $HEALTH_RESP"
    echo "[FAIL] Stage 5: Health check failed after rollback"
    exit 1
fi

echo "=================================================="
echo " Local Demo Complete: ALL STAGES PASSED           "
echo "=================================================="
