# Cloud Security Lab

A containerized cybersecurity training environment featuring an attacker platform (Kali Linux) and a deliberately weak target (Metasploitable-style Ubuntu), running Kubernetes-based, per-student multi-tenant isolation for classroom cybersecurity training.

> **Scope:**  Developed and tested on macOS and Windows (WSL2). Uses Docker Desktop and a `kind` Kubernetes cluster (2 nodes: 1 control-plane + 1 worker) with Calico CNI (Docker Desktop's built-in Kubernetes is not supported).

A live, read-only dashboard for presenting cluster state (`cloudsec-dashboard/`) is also available — see [`cloudsec-dashboard/README.md`](cloudsec-dashboard/README.md).

---

## Resources

- **[Video Demo](https://drive.google.com/file/d/1ff828gYAnVpAHnqJ-AfDcPzyX9lMNcku/view?usp=share_link)** — Complete walkthrough of the lab environment and attack scenarios
- **[PowerPoint Presentation](https://docs.google.com/presentation/d/1IAG22rD7rTuRvfWHQe3qVGbqQ8fNRR8q/edit?usp=sharing&ouid=103749880608451520115&rtpof=true&sd=true)** — Lab overview, architecture, and learning objectives

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

## License

See [LICENSE](LICENSE).
