#!/bin/bash
set -euo pipefail
if [ $# -ne 1 ]; then
  echo "Usage: $0 <student-id>"
  echo "Example: $0 001"
  exit 1
fi

STUDENT_ID="$1"

if ! [[ "$STUDENT_ID" =~ ^[0-9]{3}$ ]]; then
  echo "Error: student-id must be a 3-digit number (e.g. 001)"
  exit 1
fi

NAMESPACE="student-${STUDENT_ID}"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/kubernetes/namespaces"
TEMPLATE_FILE="$TEMPLATE_DIR/namespace-template.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Template not found: $TEMPLATE_FILE"
  exit 1
fi

export STUDENT_ID

# Create namespace
envsubst < "$TEMPLATE_FILE" | kubectl apply -f -

echo "Applying Pod Security Admission labels..."

kubectl label namespace "$NAMESPACE" \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite

echo "Namespace $NAMESPACE created and secured."
kubectl get namespace "$NAMESPACE" --show-labels