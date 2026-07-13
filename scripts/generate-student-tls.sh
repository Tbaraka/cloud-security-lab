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
HOSTNAME="student-${STUDENT_ID}.lab.local"

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Error: namespace '$NAMESPACE' does not exist."
    echo "Run generate-student-namespace.sh first."
    exit 1
fi

if [ ! -f "./ca/lab-ca.crt" ] || [ ! -f "./ca/lab-ca.key" ]; then
    echo "Error: Lab CA not found."
    echo "Expected:"
    echo "  ./ca/lab-ca.crt"
    echo "  ./ca/lab-ca.key"
    exit 1
fi

WORKDIR=$(mktemp -d)

cleanup() {
    rm -rf "$WORKDIR"
}

trap cleanup EXIT

echo "Generating TLS certificate for ${HOSTNAME}..."

openssl genrsa -out "$WORKDIR/server.key" 2048 >/dev/null 2>&1

openssl req \
    -new \
    -key "$WORKDIR/server.key" \
    -subj "/CN=${HOSTNAME}" \
    -out "$WORKDIR/server.csr" >/dev/null 2>&1

echo "subjectAltName = DNS:${HOSTNAME}" > "$WORKDIR/san.ext"

openssl x509 \
    -req \
    -in "$WORKDIR/server.csr" \
    -CA ./ca/lab-ca.crt \
    -CAkey ./ca/lab-ca.key \
    -CAcreateserial \
    -out "$WORKDIR/server.crt" \
    -days 825 \
    -sha256 \
    -extfile "$WORKDIR/san.ext" >/dev/null 2>&1

kubectl create secret tls "${NAMESPACE}-tls" \
    -n "$NAMESPACE" \
    --cert="$WORKDIR/server.crt" \
    --key="$WORKDIR/server.key" \
    --dry-run=client -o yaml \
| kubectl apply -f -

echo ""
echo "TLS secret created successfully."

kubectl get secret "${NAMESPACE}-tls" -n "$NAMESPACE"

echo ""
echo "Hostname:"
echo "https://${HOSTNAME}"