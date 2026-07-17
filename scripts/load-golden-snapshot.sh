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

GOLDEN_FILE="/mnt/encrypted-storage-golden/golden-workspace.tar.gz"

if ! docker exec cloudsec-lab-control-plane test -f "$GOLDEN_FILE"; then
    echo "Error: golden snapshot not found at $GOLDEN_FILE"
    exit 1
fi

echo "Waiting for student-${STUDENT_ID}-work PVC to be bound and mounted..."
PVC_DIR=""
for i in $(seq 1 30); do
    PVC_DIR=$(docker exec cloudsec-lab-control-plane \
        find /mnt/encrypted-storage -maxdepth 1 -type d \
        -name "*_student-${STUDENT_ID}_student-${STUDENT_ID}-work" 2>/dev/null | head -1)
    if [ -n "$PVC_DIR" ]; then
        break
    fi
    sleep 2
done

if [ -z "$PVC_DIR" ]; then
    echo "Error: workspace directory for student-${STUDENT_ID} never appeared after 60s."
    echo "Check: kubectl get pvc student-${STUDENT_ID}-work -n student-${STUDENT_ID}"
    exit 1
fi

echo "Found workspace directory: $PVC_DIR"
echo "Loading golden snapshot..."
docker exec cloudsec-lab-control-plane bash -c "tar xzf '$GOLDEN_FILE' -C '$PVC_DIR'"

echo "Golden snapshot loaded for student-${STUDENT_ID}."
kubectl exec -it kali-attacker -n "student-${STUDENT_ID}" -- ls -la /home/kali/workspace/ 2>/dev/null || \
    echo "(Kali pod not ready yet to verify contents -- check manually.)"
