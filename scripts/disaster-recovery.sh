#!/usr/bin/env bash
# Disaster recovery: wipe compromised student namespace and redeploy clean lab
# Usage:
#   ./scripts/disaster-recovery.sh student-lab-1
#   ./scripts/disaster-recovery.sh student-lab-1 /path/to/backup-dir
set -euo pipefail

NS="${1:-student-lab-1}"
BACKUP_DIR="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> DR for $NS"

if [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/work-data.tar" ]]; then
  echo "Backup will be restored after clean redeploy: $BACKUP_DIR"
fi

# Snapshot manifests first (auto-backup)
bash "$ROOT/scripts/backup-student-lab.sh" "$NS" || true

echo "==> Deleting compromised namespace $NS"
kubectl delete namespace "$NS" --wait=true --timeout=180s || true

# Wait until gone
for i in $(seq 1 30); do
  kubectl get ns "$NS" >/dev/null 2>&1 || break
  sleep 2
done

echo "==> Recreating clean namespace + quota + RBAC"
bash "$ROOT/scripts/generate-student-namespace.sh" "$NS"
bash "$ROOT/scripts/generate-student-rbac.sh" "$NS"

echo "==> Redeploying lab workloads"
kubectl apply -f "$ROOT/kubernetes/lab/student-lab-deployments.yaml" -n "$NS"
kubectl apply -f "$ROOT/kubernetes/storage/student-storage.yaml" -n "$NS" || true
kubectl apply -f "$ROOT/kubernetes/network-policies.yaml" || true
kubectl apply -f "$ROOT/kubernetes/network-policy-allow-ingress.yaml" || true
kubectl apply -f "$ROOT/kubernetes/ingress/lab-web-ingress-hpa.yaml" -n "$NS" || true

# TLS
id="${NS#student-lab-}"
bash "$ROOT/scripts/generate-student-lab.sh" "$id" || true

kubectl -n "$NS" rollout status deploy/kali-lab --timeout=180s || true
kubectl -n "$NS" rollout status deploy/metasploitable-lab --timeout=180s || true

if [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/work-data.tar" ]]; then
  echo "==> Restoring student /work data"
  kubectl -n "$NS" wait --for=condition=Ready pod -l app=student-work --timeout=120s || true
  kubectl -n "$NS" exec -i deploy/student-work -- sh -c 'tar -x -C /work' < "$BACKUP_DIR/work-data.tar" || true
fi

echo "==> Clean environment ready"
kubectl -n "$NS" get pods,pvc,ingress,networkpolicy
echo "DR complete for $NS"
