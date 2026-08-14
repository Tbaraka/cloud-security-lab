# Secure Container Deployment Guide

## Components
- Kali (attacker) and Metasploitable-style victim images
- Docker Compose for local tooling validation
- Kind cluster `cloudsec-lab` (2 nodes: control-plane + worker) with Calico for multi-tenant orchestration

## Build
```bash
docker build -t kali-lab:latest ./kali
docker build -t metasploitable-lab:latest ./metasploitable
kind load docker-image kali-lab:latest metasploitable-lab:latest --name cloudsec-lab
```

## Deploy Compose (tooling test)
```bash
docker compose up -d --build
docker compose exec kali bash
```

## Deploy student lab on Kind
```bash
bash ./scripts/generate-student-lab.sh 001
```
Single orchestrator script — runs namespace, RBAC, network policies, target pod, TLS, storage, Kali pod, and ingress in one call.

## Security practices
- Numeric UID/GID (1000:1000) set explicitly on the Kali image — required for PVC `fsGroup` permission mapping to resolve correctly
- Pin base image digests where possible
- Scan with Trivy (`security/trivy`)
- Prefer ClusterIP + NetworkPolicy over NodePort for student labs
- Non-root where exercise design allows (Kali retains `CAP_NET_RAW`/`CAP_NET_ADMIN` for scanning and packet capture)
- `tshark` requires `setcap cap_net_raw,cap_net_admin=eip` on `dumpcap` in addition to container capabilities — container capabilities alone are not sufficient