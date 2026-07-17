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
NAMESPACE="student-${STUDENT_ID}-target"
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Error: namespace '$NAMESPACE' does not exist yet."
    exit 1
fi
if [ ! -f "./ca/wildcard.crt" ] || [ ! -f "./ca/wildcard.key" ]; then
    echo "Error: wildcard cert not found. Expected ./ca/wildcard.crt and ./ca/wildcard.key"
    exit 1
fi
kubectl create secret tls "student-${STUDENT_ID}-tls" \
    -n "$NAMESPACE" \
    --cert=./ca/wildcard.crt --key=./ca/wildcard.key \
    --dry-run=client -o yaml | kubectl apply -f -
echo "TLS secret (wildcard) applied in $NAMESPACE for student-${STUDENT_ID}.lab.local"
