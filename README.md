# Cloud Security Lab

A containerized cybersecurity training environment: an attacker platform (Kali) and a deliberately weak target (Metasploitable-style Ubuntu), moving toward Kubernetes-based, per-student multi-tenant isolation for a larger classroom deployment.

> **Scope:** Beginner-level lab, single-developer, local environment. Developed and tested on macOS; runnable on Windows via WSL2 (see Prerequisites). Requires Docker Desktop with Kubernetes enabled.
> For the full build log, testing evidence, and design-decision rationale, see [`docs/progress-report.md`](docs/progress-report.md).

---

## Current status

| Layer | Status |
|---|---|
| Docker images (Kali, Metasploitable) | ✅ Complete, tested |
| Docker Compose networking | ✅ Complete, tested |
| Trivy vulnerability scans | ✅ Scans run — findings not yet summarized |
| Kubernetes cluster | ✅ Running (Docker Desktop) |
| Namespace + ResourceQuota automation | ✅ Complete, tested |
| Network policies (Calico) | ⏳ In progress |
| RBAC | ⏳ Not started |
| Ingress + WAF | ⏳ Not started |
| Persistent storage / backup | ⏳ Not started |
| Autoscaling | ⏳ Not started |
| Monitoring (Falco/Prometheus/Grafana) | ⏳ Not started |
| Video demonstration | ⏳ Not started |

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

**3. Provision a Kubernetes namespace for a student:**
```bash
./scripts/generate-student-namespace.sh 001
kubectl get namespaces --show-labels
kubectl get resourcequota -n student-001
```

---

## Repository structure

```
.
├── docker-compose.yml
├── dockerfiles/
│   ├── kali/                # Attacker platform
│   ├── metasploitable/      # Vulnerable target
│   └── windows/             # Not containerized — see README inside
├── kubernetes/
│   ├── namespaces/          # Namespace + ResourceQuota template
│   └── network-policies/    # Calico isolation policies (in progress)
├── security/
│   ├── trivy/                # Vulnerability scan results
│   ├── gvisor/ , kata/       # Runtime isolation — evaluated, deferred
├── scripts/                  # Automation (namespace generation, etc.)
└── docs/
    └── progress-report.md    # Full build log and design rationale
```

---

## Key design decisions

A few choices in this repo are deliberate and documented in detail in the progress report — flagged here so they aren't mistaken for oversights:

- **Windows is not containerized.** See [`dockerfiles/windows/README.md`](dockerfiles/windows/README.md).
- **The Metasploitable-style target uses current Ubuntu packages, not legacy vulnerable versions.** It supports credential-based attacks (weak `msfadmin:msfadmin` login), not service-version exploits. See progress report §2.2.
- **Kali's passwordless sudo is intentional** — it's the attacker platform, not a privilege-escalation target.
- **gVisor and Kata Containers were evaluated for stronger runtime isolation and deferred** — both hit environment limitations on Docker Desktop/macOS. See progress report §5.

---

## License

See [LICENSE](LICENSE).
