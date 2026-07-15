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

TS=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="student-${STUDENT_ID}-snapshot-${TS}.tar.gz"

# Find the actual PVC data directory on the node (local-path names
# directories as pvc-<uuid>_<namespace>_<pvcname> -- match on
# namespace_pvcname since the uuid is unpredictable)
PVC_DIR=$(docker exec cloudsec-lab-control-plane \
    find /mnt/encrypted-storage -maxdepth 1 -type d \
    -name "*_student-${STUDENT_ID}_student-${STUDENT_ID}-work" | head -1)

if [ -z "$PVC_DIR" ]; then
    echo "Error: no PVC data directory found for student-${STUDENT_ID}. Is the PVC Bound?"
    exit 1
fi

echo "Snapshotting $PVC_DIR ..."
docker exec cloudsec-lab-control-plane bash -c "
    tar czf /mnt/encrypted-storage-snapshots/${SNAPSHOT_NAME} -C '${PVC_DIR}' .
"

echo "Snapshot created: ${SNAPSHOT_NAME}"
docker exec cloudsec-lab-control-plane ls -lh /mnt/encrypted-storage-snapshots/${SNAPSHOT_NAME}
