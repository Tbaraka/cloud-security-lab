#!/usr/bin/env bash
# Trigger Falco-detectable events for assignment evidence
# Usage: ./scripts/demo-falco-alert.sh <student-id>   e.g. 009
set -euo pipefail
STUDENT_ID="${1:-009}"
NS="student-${STUDENT_ID}"
TARGET_NS="${NS}-target"

echo "=== Triggering Falco-visible activity in $NS ==="
echo ""
echo "1) Shell activity"
kubectl exec -n "$NS" kali-attacker -- bash -c 'echo "Falco demo"; id; whoami' || true
echo ""
echo "2) Sensitive file probe"
kubectl exec -n "$NS" kali-attacker -- bash -c 'cat /etc/shadow 2>&1 | head -1 || true' || true
echo ""
echo "3) Reconnaissance tool (nmap)"
META_IP=$(kubectl get pod -n "$TARGET_NS" target-metasploitable -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [ -n "${META_IP:-}" ]; then
  kubectl exec -n "$NS" kali-attacker -- nmap -sT -Pn "$META_IP" -p 22 || true
else
  echo "Could not resolve target-metasploitable pod IP in $TARGET_NS"
  kubectl exec -n "$NS" kali-attacker -- nmap --version | head -2 || true
fi
echo ""
echo "=== Recent Falco logs ==="
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50 2>/dev/null | grep -i cyberlab || \
  echo "No CyberLab alerts found yet, or Falco not ready — run: kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco -f"
