#!/usr/bin/env bash
# Initialize Lab Certificate Authority (run once)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CA_DIR="${ROOT}/security/tls/ca"
mkdir -p "$CA_DIR"

if [[ -f "$CA_DIR/ca.crt" && -f "$CA_DIR/ca.key" ]]; then
  echo "Lab CA already exists at $CA_DIR"
  openssl x509 -in "$CA_DIR/ca.crt" -noout -subject -dates
  exit 0
fi

openssl genrsa -out "$CA_DIR/ca.key" 4096
openssl req -x509 -new -nodes -key "$CA_DIR/ca.key" -sha256 -days 3650 \
  -subj "/O=CloudSecurityLab/CN=Cloud Security Lab CA" \
  -out "$CA_DIR/ca.crt"

chmod 600 "$CA_DIR/ca.key"
echo "Lab CA created:"
openssl x509 -in "$CA_DIR/ca.crt" -noout -subject -dates
echo "Files: $CA_DIR/ca.crt $CA_DIR/ca.key"
