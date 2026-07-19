#!/usr/bin/env bash
# Disaster recovery: wipe compromised student namespace(s) and redeploy clean lab
# Usage:
#   ./scripts/disaster-recovery.sh student-009
#   ./scripts/disaster-recovery.sh student-009 /path/to/backup-dir
set -euo pipefail

NS_INPUT="${1:-student-lab-1}"
BACKUP_DIR="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STUDENT_ID="${NS_INPUT#student-}"
NS="student-${STUDENT_ID}"
TARGET_NS="${NS}-target"

if ! [[ "$STUDENT_ID" =~ ^[0-9]{3}$ ]]; then
    echo "Error: could not derive a 3-digit student id from '$NS_INPUT'"
    exit 1
fi

echo "==> DR for $NS"

if [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/work-data.tar" ]]; then
  echo "Backup will be restored after clean redeploy: $BACKUP_DIR"
fi

# Snapshot manifests first (auto-backup)
bash "$ROOT/scripts/backup-student-lab.sh" "$NS" || true

echo "==> Deleting compromised namespace(s)"
kubectl delete namespace "$NS" "$TARGET_NS" --wait=true --timeout=180s || true

for target_ns in "$NS" "$TARGET_NS"; do
  for i in $(seq 1 30); do
    kubectl get ns "$target_ns" >/dev/null 2>&1 || break
    sleep 2
  done
  if kubectl get ns "$target_ns" >/dev/null 2>&1; then
    echo "ERROR: $target_ns still terminating after 60s, aborting redeploy"
    exit 1
  fi
done

echo "==> Redeploying clean environment via canonical pipeline"
bash "$ROOT/scripts/generate-student-lab.sh" "$STUDENT_ID"

if [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/work-data.tar" ]]; then
  echo "==> Restoring student /work data"
  kubectl -n "$NS" wait --for=condition=Ready pod/kali-attacker --timeout=120s || true
  kubectl -n "$NS" exec -i kali-attacker -- sh -c '
    rm -rf /tmp/restore-tmp && mkdir -p /tmp/restore-tmp &&
    tar -x --no-same-owner --no-same-permissions -m -C /tmp/restore-tmp &&
    cp -r /tmp/restore-tmp/. /home/kali/workspace/ &&
    rm -rf /tmp/restore-tmp
  ' < "$BACKUP_DIR/work-data.tar"
fi

echo "==> Clean environment ready"
kubectl -n "$NS" get pods,pvc,ingress,networkpolicy
kubectl -n "$TARGET_NS" get pods,networkpolicy
echo "DR complete for $NS"
