#!/usr/bin/env bash
# Trigger Falco-detectable events for assignment evidence
set -euo pipefail

NS="${1:-student-lab-1}"

echo "=== Triggering Falco-visible activity in $NS ==="
echo ""

echo "1) Shell activity"
kubectl exec -n "$NS" deploy/kali-lab -- bash -c 'echo "Falco demo"; id; whoami' || true

echo ""
echo "2) Sensitive file probe"
kubectl exec -n "$NS" deploy/kali-lab -- bash -c 'cat /etc/shadow 2>&1 | head -1 || true' || true

echo ""
echo "3) Reconnaissance tool (nmap)"
META_IP=$(kubectl get pod -n "$NS" -l app=metasploitable-lab -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
if [ -n "${META_IP:-}" ]; then
  kubectl exec -n "$NS" deploy/kali-lab -- nmap -sT -Pn "$META_IP" -p 22 || true
else
  kubectl exec -n "$NS" deploy/kali-lab -- nmap --version | head -2 || true
fi

echo ""
echo "=== Recent Falco logs ==="
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50 2>/dev/null || \
  echo "Falco not ready — run: kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco -f"
