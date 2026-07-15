#!/usr/bin/env bash
# Provision TLS for a student lab host (Ingress HTTPS)
# Usage:
#   ./scripts/generate-student-lab.sh 001
#   ./scripts/generate-student-lab.sh all
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CA_DIR="${ROOT}/security/tls/ca"
OUT_DIR="${ROOT}/security/tls/students"
NS_PREFIX="${NS_PREFIX:-student-lab-}"

if [[ ! -f "$CA_DIR/ca.crt" || ! -f "$CA_DIR/ca.key" ]]; then
  echo "Lab CA missing. Run: bash ./scripts/init-lab-ca.sh"
  exit 1
fi

provision_one() {
  local id="$1"
  # Normalize: 001 -> student-lab-1 style used in this project, or student-001
  local ns host
  if [[ "$id" =~ ^[0-9]+$ ]]; then
    # strip leading zeros for namespace match with existing student-lab-1
    local num=$((10#$id))
    ns="${NS_PREFIX}${num}"
    host="student-${num}.lab.local"
  else
    ns="$id"
    host="${id}.lab.local"
  fi

  local work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN

  mkdir -p "$OUT_DIR/$ns"

  echo "==> Provisioning TLS for namespace=$ns host=$host"

  openssl genrsa -out "$work/tls.key" 2048
  openssl req -new -key "$work/tls.key" \
    -subj "/O=CloudSecurityLab/CN=$host" \
    -addext "subjectAltName=DNS:$host,DNS:lab.local,DNS:localhost" \
    -out "$work/tls.csr"

  openssl x509 -req -in "$work/tls.csr" \
    -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
    -out "$work/tls.crt" -days 825 -sha256 \
    -extfile <(printf "subjectAltName=DNS:%s,DNS:lab.local,DNS:localhost" "$host")

  # Ensure namespace exists (best-effort)
  kubectl get ns "$ns" >/dev/null 2>&1 || \
    bash "$ROOT/scripts/generate-student-namespace.sh" "$ns" || true

  kubectl -n "$ns" create secret tls lab-tls \
    --cert="$work/tls.crt" \
    --key="$work/tls.key" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Keep a copy for docs (no private key in git ideally — key stays out if gitignored)
  cp "$work/tls.crt" "$OUT_DIR/$ns/tls.crt"
  cp "$CA_DIR/ca.crt" "$OUT_DIR/$ns/ca.crt"

  echo "Success: TLS Secret lab-tls created/updated in namespace $ns"
  echo "Certificate CN/SAN host: $host (+ lab.local)"
}

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <student-id|all>"
  echo "Example: $0 001"
  echo "Example: $0 all"
  exit 1
fi

ARG="$1"
if [[ "$ARG" == "all" ]]; then
  # Provision for existing student-lab-* namespaces
  mapfile -t NSS < <(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -E '^student-lab-' || true)
  if [[ ${#NSS[@]} -eq 0 ]]; then
    echo "No student-lab-* namespaces found."
    exit 1
  fi
  for ns in "${NSS[@]}"; do
    id="${ns#student-lab-}"
    provision_one "$id"
  done
else
  provision_one "$ARG"
fi
