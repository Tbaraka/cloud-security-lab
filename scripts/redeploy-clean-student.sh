#!/bin/bash
set -uo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <student-id>"
    exit 1
fi

STUDENT_ID=$1
if ! [[ "$STUDENT_ID" =~ ^[0-9]{3}$ ]]; then
    echo "Error: student-id must be a 3-digit number (e.g. 001)"
    exit 1
fi

NAMESPACE="student-${STUDENT_ID}"
TARGET_NAMESPACE="student-${STUDENT_ID}-target"

echo "=========================================="
echo "CLEAN REDEPLOY: student-${STUDENT_ID}"
echo "This will DESTROY and rebuild both namespaces."
echo "=========================================="
read -p "Type the student ID (${STUDENT_ID}) to confirm: " CONFIRM
if [ "$CONFIRM" != "$STUDENT_ID" ]; then
    echo "Confirmation did not match. Aborting."
    exit 1
fi

echo ""
echo "=== Tearing down existing namespaces ==="
kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=true
kubectl delete namespace "$TARGET_NAMESPACE" --ignore-not-found --wait=true

echo ""
echo "=== Re-provisioning from scratch ==="
if ! ./scripts/generate-student-lab.sh "$STUDENT_ID"; then
    echo "ERROR: re-provisioning failed for student-${STUDENT_ID}"
    exit 1
fi

if [ ! -f "/tmp/golden-workspace.tar.gz" ]; then
    docker cp cloudsec-lab-control-plane:/mnt/encrypted-storage-golden/golden-workspace.tar.gz /tmp/golden-workspace.tar.gz 2>/dev/null || true
fi

echo ""
echo "=== Restoring golden starter workspace ==="
PVC_DIR=$(docker exec cloudsec-lab-control-plane \
    find /mnt/encrypted-storage -maxdepth 1 -type d \
    -name "*_student-${STUDENT_ID}_student-${STUDENT_ID}-work" | head -1)

if [ -z "$PVC_DIR" ]; then
    echo "WARNING: could not find workspace PVC directory -- skipping golden restore."
else
    docker exec cloudsec-lab-control-plane bash -c "
        tar xzf /mnt/encrypted-storage-golden/golden-workspace.tar.gz -C '${PVC_DIR}'
    "
    echo "Golden workspace restored into ${PVC_DIR}"
fi

echo ""
echo "=========================================="
echo "Clean redeploy complete for student-${STUDENT_ID}"
echo "=========================================="
