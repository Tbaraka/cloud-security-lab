# Cloud Security Lab — Progress Report

> **Project:** Cloud-based cybersecurity training lab (containerized attacker/target environment, moving toward Kubernetes-based multi-tenant isolation)

**Scope:** Beginner-level lab, single-developer, local environment (macOS with Docker Desktop and Kubernetes enabled)

**Current status:** Docker/Compose layer complete and verified. Kubernetes namespace automation and resource quota enforcement complete and verified. Network policy enforcement not yet applied.

*This is a living document — update sections as work progresses rather than appending a new log each time.*

---

# Table of Contents

* [1. Environment](#1-environment)
* [2. Containers Built](#2-containers-built)
  * [2.1 Kali (Attacker Platform)](#21-kali-attacker-platform)
  * [2.2 Metasploitable-style Victim](#22-metasploitable-style-victim)
  * [2.3 Windows Target](#23-windows-target-not-containerized)
* [3. Docker Networking](#3-docker-networking)
* [4. Security Scanning](#4-security-scanning)
* [5. Runtime Isolation](#5-runtime-isolation-gvisor--kata-containers)
* [6. Kubernetes Namespace Automation](#6-kubernetes-namespace-automation-and-student-isolation)
* [7. Remaining Work](#7-remaining-work)
* [8. Housekeeping](#8-housekeeping)
* [Overall Progress](#overall-progress)

---

# 1. Environment

| Component | Details |
|---|---|
| **Host OS** | macOS (Apple Silicon) |
| **Container Runtime** | Docker Desktop |
| **Kubernetes** | Docker Desktop built-in cluster (`docker-desktop`) |
| **Deployment** | Docker Compose (dev/testing) + Kubernetes manifests (orchestration/isolation) |
| **Current phase** | Docker layer complete; Kubernetes migration in progress |

---

# 2. Containers Built

## 2.1 Kali (Attacker Platform)

**Base image:** `kalilinux/kali-rolling`, **pinned by digest** for reproducibility
(`sha256:776d57c9d607faafef9957073b0b5a05b0d1115e5728777a8fc5588827cfd249`)

**Installed tools:** nmap, net-tools, iputils-ping, dnsutils, tcpdump, wireshark-common, metasploit-framework, curl, wget, git, python3/pip, sudo, vim, nano

**User configuration:** Non-root `student` account, with **passwordless sudo**. This is intentional, not an oversight — sudo restriction is not part of this container's threat model, because Kali is the attacker platform, not something students are meant to escalate privileges *on*. If a future exercise ever uses Kali as a target instead of an attacker, this decision should be revisited.

**Docker capabilities required:**
```yaml
cap_add:
  - NET_RAW
  - NET_ADMIN
```
Without these, nmap fails with `Operation not permitted` even when run as root inside the container — this is a Docker capability restriction, not a Kali/Linux permission issue. Being root *inside* a container does not grant the underlying kernel capabilities Docker withholds by default.

**Interactive shell:** Compose sets `tty: true` and `stdin_open: true`. Without these, the container's `CMD ["/bin/bash"]` exits immediately on `docker compose up -d` (no terminal attached, bash hits EOF) — the container needs a pseudo-terminal to stay alive for `exec` access.

---

## 2.2 Metasploitable-style Victim

**Base image:** `ubuntu:24.04`, **pinned by digest**
(`sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`)

**Installed services:** Apache2, OpenSSH server, vsftpd

**Weak credentials (intentional):** `msfadmin:msfadmin`

**Design scope decision:** This container supports **credential-based attacks** (brute force, default-password exploitation) using current, patched Ubuntu 24.04 packages. It does **not** reproduce the classic Metasploitable2 image's backdoored/vulnerable *service versions* (e.g. vsftpd 2.3.4, which current Ubuntu repos don't provide). This is a deliberate scope boundary: if future exercises require service-version exploits, either the real Metasploitable2 image or a hand-pinned old-package build is a separate, larger task — not something this Dockerfile currently claims to support.

**Service startup:** A custom `entrypoint.sh` starts sshd, apache2, and vsftpd in sequence (containers have no systemd, so services don't start automatically the way they would on a normal Ubuntu install).

Startup was validated more than once, including one run where the container log appeared to stop after Apache with no vsftpd line — this looked like a silent failure caused by `set -e` killing the script mid-sequence. On investigation, this turned out to be a **timing artifact**: `docker logs` was checked before the entrypoint script had finished writing its output, not an actual service failure. Confirmed via `service vsftpd status` and a full, unhurried log read that all three services start reliably. This is noted here because it's a real methodology point: a passing state observed too early can look identical to a failure, and the fix was to add a short delay before checking rather than trusting the first read.

**Verification:** Nmap scan from Kali confirmed exactly the expected ports:

| Port | Service |
|---|---|
| 21 | FTP |
| 22 | SSH |
| 80 | HTTP |

No unexpected services detected on the default top-1000 port scan.

---

## 2.3 Windows Target (Not Containerized)

Windows was intentionally **not** containerized. Reasons:

- Windows containers require a Windows host (unavailable in this dev environment — macOS/Docker Desktop).
- Even on a Windows host, Windows containers share the host kernel, which doesn't reproduce what most Windows security exercises actually target (registry behavior, service-control-manager semantics, driver interaction).
- A minimal Windows Server Core container (smallest available base) has no GUI, browser, or Office — no attack surface for typical introductory exercises (RDP, client-side payloads, SMB/AD attacks), even if it were built successfully.

**Recommended future path:** **KubeVirt** (runs a Windows VM as a native Kubernetes object, fitting the same namespace/RBAC model as the rest of this lab) or a standalone VM outside the cluster.

**Correction during development:** Kata Containers was initially considered as a possible Windows isolation option, but Kata's guest kernel support is **Linux-only** — there is no mainstream Windows guest path. This was caught and corrected; Kata is discussed only in the context of Linux workload isolation (§5), not as a Windows option.

Full reasoning: [`dockerfiles/windows/README.md`](../dockerfiles/windows/README.md).

---

# 3. Docker Networking

A custom bridge network named `cyberlab` was created in `docker-compose.yml`; both containers attach to it.

Validated:
- Docker's embedded DNS resolves service names correctly (Kali reaches `metasploitable` by name).
- Nmap scans from Kali against the Metasploitable service succeed.

Hardcoded `container_name` entries were removed from both services — they would block running more than one instance of each container, which conflicts with the eventual goal of per-student isolated environments. (Per-student scaling is being handled via Kubernetes namespaces, not by scaling Compose services — see §6.)

---

# 4. Security Scanning

Both images were scanned with **Trivy**:
```
security/trivy/kali-scan.txt (or kali-vuln-scan.txt — filenames need reconciling, see §7)
security/trivy/metasploitable-vuln-scan.txt
```

**Two categories of findings, kept distinct in reporting:**

- **Routine CVEs** from base-image package aging — expected, not being "fixed" by patching, since patching could undermine the target's intended fidelity for its purpose.
- **Intentional lab weaknesses** (e.g. `msfadmin:msfadmin`, exposed FTP/SSH) — these are *not* caught by a CVE scanner, since Trivy scans package vulnerabilities, not credential policy. This distinction matters for the final report: Trivy output alone does not capture "why this lab is exploitable," and both should be presented together, not conflated.

**Open item:** scan output files have not yet been reviewed in detail or summarized — running the scan is done, interpreting it for the report is not.

---

# 5. Runtime Isolation (gVisor / Kata Containers)

Both were evaluated as options for stronger container isolation, specifically motivated by Kali running actual exploitation tooling — an adversarial workload where the isolation boundary matters more than for passive infrastructure (e.g. a monitoring container).

## Kata Containers
VM-backed isolation (a real lightweight VM per container, not just syscall interception) — the architecturally stronger choice for isolating an attacker container specifically, since it defends against kernel-level exploits, not just typical container escapes.

**Not implemented:** Kata requires nested virtualization support from the host. Docker Desktop on macOS runs everything inside its own Linux VM already, and reliable nested virtualization inside that layer is not a standard supported path — attempting it was judged likely to cost significant time for uncertain payoff at this project's scope.

## gVisor
Lighter alternative — user-space syscall interception rather than a full VM boundary. Weaker isolation than Kata against kernel-level exploits, but doesn't need nested virtualization, so it looked like the more practical fit for this environment.

**Attempted:**
```bash
docker run --rm --runtime=runsc hello-world
```
**Result:**
```
docker: Error response from daemon: unknown or invalid runtime name: runsc
```
gVisor's runtime isn't installed/registered in Docker Desktop's VM, and doing so isn't a standard, well-documented path on macOS the way it is on native Linux Docker hosts.

**Status: deferred, not deployed**, for both. This is a scoped, justified engineering decision given the beginner-lab timeline and host constraints — not an oversight — but it needs to be written up explicitly in `security/gvisor/README.md` and `security/kata/README.md` before final submission, following the same pattern as the Windows decision in §2.3. **This documentation has not yet been written as of this report.**

---

# 6. Kubernetes Namespace Automation and Student Isolation

Docker Desktop's built-in Kubernetes was enabled and confirmed running:
```bash
kubectl cluster-info
```
returned a healthy control plane (context: `docker-desktop`).

## Namespace provisioning
Rather than hand-writing per-student YAML files (which doesn't scale to 200 students), a template + script pattern was used:

```
kubernetes/namespaces/namespace-template.yaml   # Namespace + ResourceQuota, parameterized
scripts/generate-student-namespace.sh            # takes a student ID, applies the template via envsubst
```

## Resource quotas
Every student namespace receives:

| Resource | Value |
|---|---:|
| CPU request | 1 CPU |
| CPU limit | 2 CPUs |
| Memory request | 1 GiB |
| Memory limit | 2 GiB |
| Max pods | 5 |

This prevents one student's workload from starving others on a shared cluster — a real requirement given the brief's "200+ concurrent students" scenario, not just a nice-to-have.

## Validation
- `student-001` and `student-002` namespaces created successfully, with labels `lab=cloudsec`, `student-id=<id>` — these labels are what the eventual Calico NetworkPolicy will select on, so they were set up now rather than retrofitted later.
- **ResourceQuota behavior confirmed:** once a namespace has CPU/memory limits set via ResourceQuota, Kubernetes requires every pod in that namespace to explicitly declare `resources.requests` and `resources.limits` — pod creation is otherwise rejected outright. `kubectl run` one-liners can't set these fields, so a full pod manifest (`kubernetes/test-pod.yaml`) was used for testing instead.
- Test pods deployed successfully into both namespaces using the existing locally-built `cloudsec-lab2-kali` image — Docker Desktop's Kubernetes shares the local Docker image store with Compose builds, so no registry push was needed in this environment. (This may not hold true in other Kubernetes setups, e.g. kind or a cloud cluster — worth remembering if the environment changes later.)

## Key finding: namespaces alone do not provide network isolation
With no NetworkPolicy applied, a pod in `student-001` successfully pinged a pod in `student-002` across the namespace boundary:
```
2 packets transmitted, 2 received, 0% packet loss
```
This confirms, with direct evidence rather than assumption, that Kubernetes namespaces are an organizational boundary only. Network isolation requires a `NetworkPolicy` enforced by a compatible CNI (Calico, in this project's case). **This successful cross-namespace ping is being kept as "before" evidence** — the plan is to re-run the identical test after applying `default-deny.yaml` and `allow-student-internal.yaml`, so the report can show a concrete before/after rather than just presenting policy YAML with no proof it does anything.

---

# 7. Remaining Work

**Networking**
- Review and apply `kubernetes/network-policies/default-deny.yaml` and `allow-student-internal.yaml`
- Re-run the cross-namespace ping test to confirm traffic is now blocked
- Reconcile duplicate/inconsistently-named Trivy scan files in `security/trivy/`

**Security**
- Write up `security/gvisor/README.md` and `security/kata/README.md` (decision made, not yet documented)
- Implement RBAC (Role/RoleBinding per student namespace)
- Summarize Trivy scan findings for the final report

**Infrastructure**
- NGINX Ingress + ModSecurity WAF
- TLS termination
- Persistent storage with encryption (note: `local-path-storage` provisioner already present in Docker Desktop's Kubernetes — may reduce setup work here)
- Automated backups (Velero or equivalent)

**Scaling & monitoring**
- Horizontal Pod Autoscaler / KEDA
- Falco (runtime compromise detection — needed before any "automated recovery on compromise" claim has a real mechanism behind it)
- Prometheus + Grafana

**Deliverables**
- Security benchmark results (distinct document)
- Disaster recovery procedures (distinct document)
- Performance tuning recommendations
- 8-minute video demonstration

---

# 8. Housekeeping

The Docker environment was cleaned of duplicate images and stray debugging containers accumulated during manual testing (`kali-lab`, `metasploitable-lab`, and a couple of unrelated scratch containers). Before deleting anything, mounts, volumes, and repo file timestamps were checked to confirm no unique data would be lost — nothing was.

`ubuntu:24.04` is intentionally retained as a base image (required by the Metasploitable Dockerfile's `FROM` line), even though no running container currently uses it directly.

---

# Overall Progress

| Component | Status |
|---|---|
| Docker images | ✅ Complete |
| Docker Compose networking | ✅ Complete |
| Trivy scans run | ✅ Complete |
| Trivy findings reviewed/summarized | ⏳ Not started |
| Kubernetes cluster | ✅ Running |
| Namespace + quota automation | ✅ Complete |
| Network policies | ⏳ In progress |
| RBAC | ⏳ Not started |
| Ingress & WAF | ⏳ Not started |
| Persistent storage / backup | ⏳ Not started |
| Disaster recovery | ⏳ Not started |
| Autoscaling | ⏳ Not started |
| Monitoring (Falco/Prometheus/Grafana) | ⏳ Not started |
| gVisor/Kata documentation | ⏳ Not started |
| Video demonstration | ⏳ Not started |
