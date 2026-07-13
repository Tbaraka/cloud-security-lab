#!/bin/bash
set -euo pipefail

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

echo "=== Step 1: Create Namespace ==="
./scripts/generate-student-namespace.sh "$STUDENT_ID"

echo ""
echo "=== Step 2: Configure RBAC ==="
./scripts/generate-student-rbac.sh "$STUDENT_ID"

echo ""
echo "=== Step 3: Apply Network Policies ==="
kubectl apply -n "$NAMESPACE" -f kubernetes/network-policies/default-deny.yaml
kubectl apply -n "$NAMESPACE" -f kubernetes/network-policies/allow-student-internal.yaml

POLICY_COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$POLICY_COUNT" -lt 2 ]; then
    echo "ERROR: expected 2 NetworkPolicies in $NAMESPACE, found $POLICY_COUNT"
    exit 1
fi

ACTUAL_PSA=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')

echo ""
echo "=========================================="
echo "✅ Student environment ready"
echo "Namespace : $NAMESPACE"
echo "RBAC      : Configured"
echo "PSA       : $ACTUAL_PSA"
echo "Network   : $POLICY_COUNT policies applied"
echo "=========================================="