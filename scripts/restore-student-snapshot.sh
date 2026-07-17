#!/bin/bash
set -uo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <student-id> <snapshot-filename>"
    echo "  List available snapshots with: docker exec cloudsec-lab-control-plane ls /mnt/encrypted-storage-snapshots"
    exit 1
fi

STUDENT_ID=$1
SNAPSHOT_FILE=$2
NAMESPACE="student-${STUDENT_ID}"

if ! [[ "$STUDENT_ID" =~ ^[0-9]{3}$ ]]; then
    echo "Error: student-id must be a 3-digit number (e.g. 001)"
    exit 1
fi

if ! docker exec cloudsec-lab-control-plane test -f "/mnt/encrypted-storage-snapshots/${SNAPSHOT_FILE}"; then
    echo "Error: snapshot file not found: ${SNAPSHOT_FILE}"
    exit 1
fi

PVC_DIR=$(docker exec cloudsec-lab-control-plane \
    find /mnt/encrypted-storage -maxdepth 1 -type d \
    -name "*_student-${STUDENT_ID}_student-${STUDENT_ID}-work" | head -1)

if [ -z "$PVC_DIR" ]; then
    echo "Error: no PVC data directory found for student-${STUDENT_ID}."
    exit 1
fi

echo "Stopping kali-attacker pod (releases the mount before we overwrite files)..."
kubectl delete pod kali-attacker -n "$NAMESPACE" --ignore-not-found --wait=true

echo "Clearing current workspace contents..."
docker exec cloudsec-lab-control-plane bash -c "rm -rf '${PVC_DIR:?}'/* '${PVC_DIR:?}'/.[!.]* 2>/dev/null || true"

echo "Restoring from ${SNAPSHOT_FILE} ..."
docker exec cloudsec-lab-control-plane bash -c "
    tar xzf /mnt/encrypted-storage-snapshots/${SNAPSHOT_FILE} -C '${PVC_DIR}'
"

echo "Recreating kali-attacker pod..."
export STUDENT_ID
envsubst < kubernetes/kali-pod-template.yaml | kubectl apply -f -

echo "Restore complete for student-${STUDENT_ID} from ${SNAPSHOT_FILE}"
