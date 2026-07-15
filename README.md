# Cloud Security Lab

A containerized cybersecurity training environment: an attacker platform (Kali) and a deliberately weak target (Metasploitable-style Ubuntu), running Kubernetes-based, per-student multi-tenant isolation for a larger classroom deployment.

> **Scope:** Beginner-level lab, single-developer, local environment. Developed and tested on macOS; runnable on Windows via WSL2 (see Prerequisites). Requires Docker Desktop and a `kind` Kubernetes cluster (Docker Desktop's built-in Kubernetes does not support the Calico CNI this project needs — see [`docs/full-run-through.md`](docs/full-run-through.md)).
> For the full build log and design-decision rationale, see [`docs/progress-report.md`](docs/progress-report.md). For the complete first-to-end command sequence, see [`docs/full-run-through.md`](docs/full-run-through.md).

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
| Ingress + WAF (ModSecurity, detection-only) | ✅ Complete, tested (community ingress-nginx used deliberately despite March 2026 retirement — see docs) |
| TLS termination | ✅ Complete, tested (self-signed lab CA, wildcard cert) |
| Encrypted persistent storage (LUKS) | ✅ Complete, tested |
| Automated backup | ✅ Complete, tested — backups currently on same disk as source (3-2-1 gap, open) |
| Snapshot management (on-demand create/restore) | ✅ Complete, tested (real round-trip verified) |
| Golden snapshot / quick clean-environment deploy | ✅ Complete, tested |
| Compromise detection (Falco) | ⚠️ Partial — installed, custom rules loaded; outbound-connection rule verified working, container-breakout rule confirmed broken (unresolved) |
| Automated recovery triggered by Falco alerts | ⏳ Not started — detection exists, no automatic action wired yet |
| Autoscaling / pod anti-affinity | ⏳ Scoping decision pending — cluster is currently single-node, which limits both features meaningfully (see docs) |
| Monitoring (Prometheus/Grafana) | ⏳ Not started |
| Video demonstration | ⏳ Not started |

For the exact commands to run this project start to finish, see [`docs/full-run-through.md`](docs/full-run-through.md).

---

## Prerequisites

- Docker Desktop, with **Kubernetes enabled** under Settings → Kubernetes
- `kubectl`, `helm`, `envsubst` (part of `gettext`)
- A bash-compatible shell (see platform notes below)

### macOS
```bash
brew install gettext helm
brew link --force gettext
```

### Windows
Run everything through **WSL2** — this project's scripts are bash-based and depend on `envsubst`, unavailable in PowerShell/cmd by default.
```powershell
wsl --install
```
Then inside WSL2:
```bash
sudo apt update && sudo apt install gettext-base
```
Enable Docker Desktop's WSL2 integration (Settings → Resources → WSL Integration), and clone this repo inside the WSL2 filesystem, not `/mnt/c`.

---

## Quick start

**1. Docker Compose layer:**
```bash
docker compose up -d --build
```

**2. Kubernetes cluster (kind + Calico — Docker Desktop's built-in Kubernetes will not work):**
```bash
kind create cluster --name cloudsec-lab --config kind-config.yaml
kubectl config use-context kind-cloudsec-lab
kubectl apply -f calico/calico.yaml
```

**3. Provision a fully isolated student environment (namespace, RBAC, network policies, TLS, storage, target, Kali, Ingress — one command):**
```bash
chmod +x scripts/*.sh
./scripts/generate-student-lab.sh 001
```

**4. Deploy a clean starter workspace:**
```bash
./scripts/load-golden-snapshot.sh 001
```

**5. Check everything at once:**
```bash
./scripts/show-student-env.sh 001
```

Full step-by-step, every stage in order with expected output: **[`docs/full-run-through.md`](docs/full-run-through.md)**.

---

## Key design decisions

- **Community `ingress-nginx` used despite its March 2026 retirement.** Deliberate, scoped choice — best-documented ModSecurity/WAF integration, acceptable given this runs in an isolated local cluster, not internet-facing. See `docs/full-run-through.md` §7.
- **TLS uses a self-signed lab CA, not cert-manager/Let's Encrypt** — no public DNS exists for ACME validation to reach.
- **Storage encryption is LUKS-based, not CSI VolumeSnapshots** — `local-path-provisioner` has no CSI driver underneath it, so snapshotting is tar-based, not native Kubernetes snapshots.
- **Windows is not containerized.** See `dockerfiles/windows/README.md`.
- **Kali's passwordless sudo is intentional** — it's the attacker platform, not a privilege-escalation target.
- **PSA (Restricted/Baseline) blocks Kali's NET_RAW/NET_ADMIN needs** — resolved by splitting each student into two namespaces (`student-XXX` privileged for Kali, `student-XXX-target` baseline for Metasploitable).
- **Cluster is single-node** — this is a known, current limitation directly affecting the autoscaling/anti-affinity requirement; a scoping decision is pending rather than silently worked around.

---

## License

See [LICENSE](LICENSE).