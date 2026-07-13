#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <student-id>"
    exit 1
fi

STUDENT_ID=$1
export STUDENT_ID

# Create namespace
envsubst < kubernetes/namespaces/namespace-template.yaml | kubectl apply -f -

NAMESPACE="student-${STUDENT_ID}"

echo "Applying Pod Security Admission labels..."

kubectl label namespace "$NAMESPACE" \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted \
    --overwrite

echo "Namespace $NAMESPACE created and secured."