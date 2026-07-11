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

if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Error: namespace '$NAMESPACE' does not exist."
    echo "Run ./scripts/generate-student-namespace.sh $STUDENT_ID first."
    exit 1
fi

export STUDENT_ID

envsubst < kubernetes/rbac/student-rbac-template.yaml \
  | kubectl apply -n "$NAMESPACE" -f -

echo "RBAC applied for $NAMESPACE."

OTHER_NAMESPACE=$(kubectl get namespaces -l lab=cloudsec -o jsonpath='{.items[*].metadata.name}' \
  | tr ' ' '\n' | grep -v "^${NAMESPACE}$" | head -n1 || true)

if [ -n "$OTHER_NAMESPACE" ]; then
  echo ""
  echo "Cross-namespace permission check (against $OTHER_NAMESPACE):"
  RESULT=$(kubectl auth can-i create pods \
    --as=system:serviceaccount:${NAMESPACE}:student-${STUDENT_ID} \
    -n "$OTHER_NAMESPACE" 2>&1) || true
  case "$RESULT" in
    "yes") echo "WARNING: ServiceAccount can access another namespace!" ;;
    "no")  echo "Confirmed: cross-namespace access denied." ;;
    *)     echo "ERROR: unexpected result from permission check:"; echo "$RESULT" ;;
  esac
else
  echo ""
  echo "Only one student namespace exists — skipping cross-namespace check."
fi
