#!/usr/bin/env bash
# Install Falco on Kind cybersec lab cluster
set -euo pipefail

export PATH="$HOME/bin:$PATH"
cd "$(dirname "$0")/.."

if ! command -v helm >/dev/null 2>&1; then
  echo "Helm is required. Install from https://helm.sh/docs/intro/install/"
  exit 1
fi

helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --values monitoring/falco/values.yaml \
  --wait \
  --timeout 10m

echo ""
echo "Falco installed."
kubectl -n falco get pods -o wide
echo ""
echo "Watch alerts with:"
echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco -f"
