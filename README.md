# Cloud Security Lab

A containerized cybersecurity training environment: an attacker platform (Kali) and a deliberately weak target (Metasploitable-style Ubuntu), moving toward Kubernetes-based, per-student multi-tenant isolation for a larger classroom deployment.

> **Scope:** Beginner-level lab, single-developer, local environment. Developed and tested on macOS; runnable on Windows via WSL2 (see Prerequisites). Requires Docker Desktop and a `kind` Kubernetes cluster (Docker Desktop's built-in Kubernetes does not support the Calico CNI this project needs — see [`docs/full-run-through.md`](docs/full-run-through.md)).
> For the full build log and design-decision rationale, see [`docs/progress-report.md`](docs/progress-report.md). For the complete first-to-end command sequence, see [`docs/full-run-through.md`](docs/full-run-through.md).

---

## Current status

| Layer | Status |
|---|---|
| Docker images (Kali, Metasploitable) | ✅ Complete, tested |
| Docker Compose networking | ✅ Complete, tested |
| Trivy vulnerability scans | ✅ Scans run — findings not yet summarized |
| Kubernetes cluster | ✅ Running (`kind`, Calico installed) |
| Namespace + ResourceQuota automation | ✅ Complete, tested |
| Pod Security Admission | ✅ Labels applied — Kali capability conflict unresolved (see docs) |
| RBAC | ✅ Complete, tested (both directions, multiple students) |
| Network policies (Calico) — cross-namespace deny | ✅ Complete, tested |
| Network policies (Calico) — same-namespace allow | ⏳ Logic reviewed, not live-tested |
| Automated student provisioning (`generate-student-lab.sh`) | ✅ Complete, tested end-to-end |
| Ingress + WAF | ⏳ Not started |
| Persistent storage / backup | ⏳ Not started |
| Autoscaling | ⏳ Not started |
| Monitoring (Falco/Prometheus/Grafana) | ⏳ Not started |
| Video demonstration | ⏳ Not started |

For the exact commands to run this project start to finish, see [`docs/full-run-through.md`](docs/full-run-through.md). For what's been verified vs. still open, see [`docs/session-summary-2026-07-13.md`](docs/session-summary-2026-07-13.md).

---

## Prerequisites

- Docker Desktop, with **Kubernetes enabled** under Settings → Kubernetes
- `kubectl`
- `envsubst` (part of `gettext`)
- A bash-compatible shell (see platform notes below)

### macOS
```bash
brew install gettext
brew link --force gettext
```
Everything below runs in Terminal as-is.

### Windows
This project's automation (`scripts/*.sh`) is written in bash and depends on `envsubst`, neither of which is available in PowerShell or cmd.exe by default. **Run everything through WSL2** (Windows Subsystem for Linux) rather than a native Windows shell — this lets you follow every command in this README unchanged.

1. Install WSL2 with a Linux distro (Ubuntu recommended):
   ```powershell
   wsl --install
   ```
2. Enable Docker Desktop's **WSL2 integration**: Docker Desktop → Settings → Resources → WSL Integration → enable it for your distro.
3. Open your WSL2 distro's terminal (not PowerShell/cmd) and install `envsubst`:
   ```bash
   sudo apt update && sudo apt install gettext-base
   ```
4. Clone/open this repo **inside the WSL2 filesystem** (e.g. `~/cloud-security-lab`), not on the Windows `C:\` drive mounted through `/mnt/c` — cross-filesystem access between WSL2 and Windows is noticeably slower and occasionally causes permission issues with scripts.
5. `kubectl` and Docker CLI commands from WSL2 talk to the same Docker Desktop engine automatically — no separate install needed inside WSL2 itself.

From this point on, every command in this README works the same in a WSL2 terminal as it does in macOS Terminal.

**Not tested on native Windows (PowerShell/cmd) without WSL2** — the bash scripts will not run there without modification.

---

## Quick start

**1. Build and run the Docker Compose environment (Kali + Metasploitable target):**
```bash
docker compose up -d --build
docker compose ps
```

**2. Test connectivity from the attacker container:**
```bash
docker compose exec kali nmap -sT metasploitable
```
Expected: ports 21 (FTP), 22 (SSH), 80 (HTTP) open.

**3. Create the Kubernetes cluster (Docker Desktop's built-in Kubernetes will not work — Calico requires `kind`):**
```bash
kind create cluster --name cloudsec-lab --config kind-config.yaml
kubectl config use-context kind-cloudsec-lab
kubectl apply -f calico/calico.yaml
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
```

**4. Provision a fully isolated student environment (namespace, RBAC, network policies, in one step):**
```bash
chmod +x scripts/*.sh
./scripts/generate-student-lab.sh 001
```

**5. Verify isolation:**
```bash
kubectl get networkpolicy -n student-001
kubectl auth can-i create pods --as=system:serviceaccount:student-001:student-001 -n student-002   # expect: no
```

Full step-by-step with expected output at each stage: [`docs/full-run-through.md`](docs/full-run-through.md).

---

## Repository structure

```
.
├── docker-compose.yml
├── kind-config.yaml
├── calico/                   # Calico CNI manifest
├── dockerfiles/
│   ├── kali/                # Attacker platform
│   ├── metasploitable/      # Vulnerable target
│   └── windows/             # Not containerized — see README inside
├── kubernetes/
│   ├── namespaces/           # Namespace + ResourceQuota template
│   ├── rbac/                 # ServiceAccount + Role + RoleBinding template
│   ├── network-policies/     # Calico isolation policies (deny + allow)
│   └── test-pod.yaml         # Isolation-testing pod manifest
├── security/
│   ├── trivy/                # Vulnerability scan results
│   ├── gvisor/ , kata/       # Runtime isolation — evaluated, deferred
├── scripts/
│   ├── generate-student-namespace.sh
│   ├── generate-student-rbac.sh
│   └── generate-student-lab.sh   # Orchestrator: runs all three stages
└── docs/
    ├── progress-report.md         # Full build log and design rationale
    ├── full-run-through.md        # Ordered, start-to-finish command sequence
    └── session-summary-*.md       # Dated summaries of specific work sessions
```

---

## Key design decisions

A few choices in this repo are deliberate and documented in detail in the progress report — flagged here so they aren't mistaken for oversights:

- **Windows is not containerized.** See [`dockerfiles/windows/README.md`](dockerfiles/windows/README.md).
- **The Metasploitable-style target uses current Ubuntu packages, not legacy vulnerable versions.** It supports credential-based attacks (weak `msfadmin:msfadmin` login), not service-version exploits. See progress report §2.2.
- **Kali's passwordless sudo is intentional** — it's the attacker platform, not a privilege-escalation target.
- **gVisor and Kata Containers were evaluated for stronger runtime isolation and deferred** — both hit environment limitations on Docker Desktop/macOS. See progress report §5.
- **Pod Security Admission (Restricted) is currently in conflict with Kali's scanning requirements.** Restricted (and Baseline) PSA both block the `NET_RAW`/`NET_ADMIN` capabilities nmap needs — this is unresolved, not silently ignored. See [`docs/session-summary-2026-07-13.md`](docs/session-summary-2026-07-13.md).

---

## License

See [LICENSE](LICENSE).