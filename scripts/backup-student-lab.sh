#!/usr/bin/env bash
# Backup student namespace manifests + PVC data (DR)
# Usage: ./scripts/backup-student-lab.sh student-lab-1
set -euo pipefail
NS="${1:-student-lab-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/backups/${NS}-${STAMP}"
mkdir -p "$OUT"
echo "==> Backing up $NS to $OUT"
kubectl get ns "$NS" -o yaml > "$OUT/namespace.yaml"
kubectl -n "$NS" get all,cm,secret,pvc,ingress,networkpolicy,role,rolebinding,sa,hpa -o yaml > "$OUT/resources.yaml" 2>/dev/null || \
  kubectl -n "$NS" get all,cm,secret,pvc,ingress,networkpolicy -o yaml > "$OUT/resources.yaml"
# Export student work files from PVC-mounted pod if present
if kubectl -n "$NS" get pod kali-attacker >/dev/null 2>&1; then
  kubectl -n "$NS" exec kali-attacker -- sh -c 'cd /home/kali/workspace && find . -mindepth 1 -print0 | tar -c --no-recursion --null -T -' > "$OUT/work-data.tar" || true
  echo "Saved /work volume archive (if available)"
fi
# Do not store private keys in plaintext backups for git — secrets are in resources.yaml; scrub TLS keys optionally
echo "$STAMP" > "$OUT/BACKUP_INFO.txt"
echo "Namespace: $NS" >> "$OUT/BACKUP_INFO.txt"
kubectl -n "$NS" get pods,pvc,ingress -o wide >> "$OUT/BACKUP_INFO.txt" || true
echo "Backup complete: $OUT"
echo "To restore: bash ./scripts/disaster-recovery.sh $OUT"
