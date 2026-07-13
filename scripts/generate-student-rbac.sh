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

# Ensure namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Error: namespace '$NAMESPACE' does not exist."
    echo "Run ./scripts/generate-student-namespace.sh $STUDENT_ID first."
    exit 1
fi

export STUDENT_ID

# Apply ServiceAccount, Role and RoleBinding
envsubst < kubernetes/rbac/student-rbac-template.yaml | kubectl apply -f -
echo "RBAC applied for $NAMESPACE."

echo ""
echo "Verifying permissions..."
echo -n "Own namespace ($NAMESPACE): "
kubectl auth can-i create pods \
    --as=system:serviceaccount:${NAMESPACE}:student-${STUDENT_ID} \
    -n "$NAMESPACE" || true

# Find another student namespace (if one exists)
OTHER_NAMESPACE=$(
    kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep '^student-' \
    | grep -v "^${NAMESPACE}$" \
    | head -n1 || true
)

if [ -n "$OTHER_NAMESPACE" ]; then
    echo -n "Other namespace ($OTHER_NAMESPACE): "
    kubectl auth can-i create pods \
        --as=system:serviceaccount:${NAMESPACE}:student-${STUDENT_ID} \
        -n "$OTHER_NAMESPACE" || true
else
    echo "Only one student namespace exists — skipping cross-namespace check."
fi

echo ""
echo "Generating 8-hour access token..."
kubectl create token "student-${STUDENT_ID}" \
    -n "$NAMESPACE" \
    --duration=8h

echo ""
echo "RBAC provisioning completed successfully."