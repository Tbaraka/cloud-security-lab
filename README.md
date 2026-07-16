# Cloud Security Lab

A containerized cybersecurity training environment featuring an attacker platform (Kali Linux) and a deliberately weak target (Metasploitable-style Ubuntu), running Kubernetes-based, per-student multi-tenant isolation for classroom cybersecurity training.

> **Scope:** Beginner-level lab, **multi-developer**, local environment. Developed and tested on macOS and Windows (WSL2). Uses Docker Desktop and a `kind` Kubernetes cluster with Calico CNI (Docker Desktop's built-in Kubernetes is not supported).
>
> For the complete build log and design rationale, see [`docs/progress-report.md`](docs/progress-report.md).
>
> For the complete deployment walkthrough, see [`docs/full-run-through.md`](docs/full-run-through.md).

---

## Current status

| Layer | Status |
|---|---|
| Docker images (Kali, Metasploitable) | ✅ Complete, tested |
| Docker Compose networking | ✅ Complete, tested |
| Trivy vulnerability scans | ✅ Scans run — findings not yet summarized |
| Kubernetes cluster | ✅ Running (`kind`, single-node, Calico installed) |
| Namespace + ResourceQuota automation | ✅ Complete, tested |
| Pod Security Admission | ✅ Labels applied — Kali capability conflict unresolved (see docs) |
| RBAC | ✅ Complete, tested (both directions, multiple students) |
| Network policies (Calico) — cross-namespace deny | ✅ Complete, tested |
| Network policies (Calico) — same-namespace allow | ⏳ Logic reviewed, not live-tested |
| Automated student provisioning (`generate-student-lab.sh`) | ✅ Complete, tested end-to-end (RBAC, TLS, storage, target, Kali, Ingress) |
| Ingress + WAF (ModSecurity, detection-only) | ✅ Complete, tested |
| TLS termination | ✅ Complete, tested |
| Encrypted persistent storage (LUKS) | ✅ Complete, tested |
| Automated backup | ✅ Complete, tested (3-2-1 backup strategy still pending) |
| Snapshot management | ✅ Complete, tested |
| Golden snapshot deployment | ✅ Complete, tested |
| Compromise detection (Falco) | ⚠️ Partial — custom rules installed; container-breakout rule still unresolved |
| Automated recovery | ⏳ Not started |
| Autoscaling / pod anti-affinity | ⏳ Pending (limited by single-node cluster) |
| Monitoring (Prometheus/Grafana) | ⏳ Not started |
| Video demonstration | ⏳ Not started |

---

## Prerequisites

- Docker Desktop
- `kind`
- `kubectl`
- `helm`
- `envsubst` (part of `gettext`)
- A bash-compatible shell

### macOS

```bash
brew install gettext helm
brew link --force gettext
```

### Windows

Run everything through **WSL2**.

```powershell
wsl --install
```

Then inside WSL2:

```bash
sudo apt update
sudo apt install gettext-base
```

Enable Docker Desktop's WSL2 integration and clone this repository inside the WSL2 filesystem rather than `/mnt/c`.

---

## Quick start

### 1. Build the Docker environment

```bash
docker compose up -d --build
```

### 2. Create the Kubernetes cluster

```bash
kind create cluster --name cloudsec-lab --config kind-config.yaml
kubectl config use-context kind-cloudsec-lab
kubectl apply -f calico/calico.yaml
```

### 3. Provision a student environment

```bash
chmod +x scripts/*.sh
./scripts/generate-student-lab.sh 001
```

### 4. Deploy the golden snapshot

```bash
./scripts/load-golden-snapshot.sh 001
```

### 5. Verify the deployment

```bash
./scripts/show-student-env.sh 001
```

For the complete walkthrough, see [`docs/full-run-through.md`](docs/full-run-through.md).

---

## Repository structure

```text
.
├── docker-compose.yml
├── dockerfiles/ / kali/ / metasploitable/
├── kubernetes/
│   ├── namespaces/
│   ├── network-policies/
│   ├── lab/
│   ├── rbac/
│   ├── ingress/
│   └── storage/
├── monitoring/falco/
├── security/
│   ├── trivy/
│   ├── tls/
│   ├── gvisor/
│   ├── kata/
│   └── psp-opa/
├── scripts/
└── docs/
```

---

## Key design decisions

- Community `ingress-nginx` is used despite its planned retirement because it provides the most mature ModSecurity/WAF integration for this local lab.
- TLS uses a self-signed lab Certificate Authority rather than cert-manager/Let's Encrypt because the lab has no public DNS.
- Storage encryption uses LUKS rather than CSI snapshots because `local-path-provisioner` has no CSI snapshot support.
- Windows is supported through WSL2; native PowerShell/cmd is not supported for the automation scripts.
- Kali intentionally has passwordless sudo because it represents the attacker workstation.
- Pod Security Admission restrictions are handled by separating Kali and Metasploitable into different namespaces.
- The current deployment targets a single-node Kind cluster, limiting autoscaling and anti-affinity.
- The Metasploitable-style target intentionally uses current Ubuntu packages configured insecurely rather than outdated vulnerable software.
- gVisor and Kata Containers were evaluated but deferred because of Docker Desktop/macOS limitations.

---

## License

See [LICENSE](LICENSE).