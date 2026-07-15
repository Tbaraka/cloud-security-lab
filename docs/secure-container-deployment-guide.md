# Secure Container Deployment Guide

## Components
- Kali (attacker) and Metasploitable-style victim images
- Docker Compose for local tooling validation
- Kind cluster `dev` with Calico for multi-tenant orchestration

## Build
```bash
docker build -t kali-lab:latest ./kali
docker build -t metasploitable-lab:latest ./metasploitable
kind load docker-image kali-lab:latest metasploitable-lab:latest --name dev
```

## Deploy Compose (tooling test)
```bash
docker compose up -d --build
docker compose exec kali bash
```

## Deploy student lab on Kind
```bash
bash ./scripts/generate-student-namespace.sh student-lab-1
bash ./scripts/generate-student-rbac.sh student-lab-1
kubectl apply -f kubernetes/lab/student-lab-deployments.yaml -n student-lab-1
bash ./scripts/generate-student-lab.sh 1   # TLS secret
```

## Security practices
- Pin base image digests where possible
- Scan with Trivy (`security/trivy`)
- Prefer ClusterIP + NetworkPolicy over NodePort for student labs
- Non-root where exercise design allows (Kali retains CAP_NET_RAW for scanning)
