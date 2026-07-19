# Cloud Security Lab

A containerized cybersecurity training environment featuring an attacker platform (Kali Linux) and a deliberately weak target (Metasploitable-style Ubuntu), running Kubernetes-based, per-student multi-tenant isolation for classroom cybersecurity training.

> **Scope:** Beginner-level lab, **multi-developer**, local environment. Developed and tested on macOS and Windows (WSL2). Uses Docker Desktop and a `kind` Kubernetes cluster (2 nodes: 1 control-plane + 1 worker) with Calico CNI (Docker Desktop's built-in Kubernetes is not supported).
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
| Trivy vulnerability scans | ✅ Scans run — not wired into CI (documented manual process) |
| Kubernetes cluster | ✅ Running (`kind`, 2-node: control-plane + worker, Calico installed) |
| Namespace + ResourceQuota automation | ✅ Complete, tested |
| Pod Security Admission | ✅ Labels applied — Kali capability conflict unresolved (see docs) |
| RBAC | ✅ Complete, tested (both directions, multiple students) |
| Network policies (Calico) — cross-namespace deny | ✅ Complete, tested |
| Network policies (Calico) — same-namespace allow | ⏳ Logic reviewed, not live-tested |
| Automated student provisioning (`generate-student-lab.sh`) | ✅ Complete, tested end-to-end (RBAC, TLS, storage, target, Kali, Ingress) |
| Ingress + WAF (ModSecurity, detection-only) | ✅ Complete, tested |
| TLS termination | ✅ Complete, tested |
| Encrypted persistent storage (LUKS) | ✅ Complete, tested — encryption-at-rest is real, but data lives inside the ephemeral kind node with no host bind-mount; does **not** survive `kind delete cluster` (see `docs/full-run-through.md` §13) |
| Automated backup | ✅ Complete, tested (3-2-1 principle still not met — same durability caveat as storage, above) |
| Snapshot management | ✅ Complete, tested (round-trip verified) — same node-lifetime durability caveat as above |
| Golden snapshot deployment | ✅ Complete, tested |
| Traffic monitoring (Wireshark/tshark) | ✅ Complete, tested — live packet capture verified in Kali pod |
| Compromise detection (Falco) | ✅ Complete, tested — custom rules (including container-breakout, now fixed) verified firing on real triggers |
| Automated recovery on compromise | ✅ Complete, tested — CRITICAL Falco alerts auto-trigger `disaster-recovery.sh` via `falco-auto-responder.sh` (dry-run/live modes) |
| Autoscaling | ✅ Complete, tested — HPA on `ingress-nginx-controller` (the real scalable component; student pods are non-scalable by design), verified scaling 1→2 under real load. Capped at 2 replicas — a hard ceiling from the kind-specific ingress manifest's use of `hostPort` (1 replica per node max), not an arbitrary limit |
| Pod anti-affinity | ✅ Complete, tested — verified replicas scheduled to separate nodes with the rule active |
| Monitoring (Prometheus/Grafana) | ⏳ Attempted — kube-prometheus-stack repeatedly destabilized the control plane under real load on this single-Mac Docker Desktop setup (multiple API server timeouts, required a control-plane container restart, a stuck-terminating namespace needing manual finalizer removal); reverted rather than force through a fragile install. A lighter-weight approach (e.g. metrics-server-only, or Grafana without the full Prometheus Operator) is the likely path if pursued further. |
| Video demonstration | N/A — delivered separately, not part of this repo |

A live, read-only dashboard for presenting cluster state (`cloudsec-dashboard/`) is also available — see [`cloudsec-dashboard/README.md`](cloudsec-dashboard/README.md).

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
kind create cluster --name cloudsec-lab --config kind/kind-config.yaml
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
├── cloudsec-dashboard/
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
- The cluster runs 2 nodes (1 control-plane + 1 worker) specifically so autoscaling and pod anti-affinity are real and verifiable rather than symbolic. Autoscaling targets `ingress-nginx-controller` (the shared, genuinely scalable component) rather than student pods, which are intentionally non-scalable, stateful, one-per-student resources.
- The Metasploitable-style target intentionally uses current Ubuntu packages configured insecurely rather than outdated vulnerable software.
- gVisor and Kata Containers were evaluated but deferred because of Docker Desktop/macOS limitations.

---

## License

See [LICENSE](LICENSE).
