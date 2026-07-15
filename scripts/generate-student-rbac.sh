#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <namespace-name>"
  echo "Example: $0 student-lab-1"
  exit 1
fi

STUDENT_ID="$1"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/kubernetes/rbac"
TEMPLATE_FILE="$TEMPLATE_DIR/student-rbac-template.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Template not found: $TEMPLATE_FILE"
  exit 1
fi

export STUDENT_ID
envsubst < "$TEMPLATE_FILE" | kubectl apply -f -

echo "RBAC provisioned for $STUDENT_ID"
kubectl get sa,role,rolebinding -n "$STUDENT_ID"
