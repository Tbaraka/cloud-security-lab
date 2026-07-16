#!/usr/bin/env bash
# Verify student RBAC permissions for a namespace
set -euo pipefail

NS="${1:-student-lab-1}"
SA="system:serviceaccount:${NS}:student-sa"
OTHER="${2:-student-lab-2}"

check() {
  local verb="$1" resource="$2" namespace="$3" expected="$4"
  local result
  result=$(kubectl auth can-i "$verb" "$resource" --as="$SA" -n "$namespace" 2>/dev/null || true)
  local status="PASS"
  [ "$result" = "$expected" ] || status="FAIL"
  printf "  %-6s %-20s ns=%-15s => %-5s (expected %s) [%s]\n" "$verb" "$resource" "$namespace" "$result" "$expected" "$status"
}

echo "=== RBAC checks for $SA ==="
echo ""
echo "Allowed in own namespace ($NS):"
check create pods "$NS" yes
check delete pods "$NS" yes
check get services "$NS" yes
check get pods/log "$NS" yes

echo ""
echo "Denied in other namespace ($OTHER):"
check create pods "$OTHER" no
check get pods "$OTHER" no

echo ""
echo "Denied cluster-wide:"
check create namespaces default no
check create clusterroles default no
