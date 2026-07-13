# Cloud Security Lab — Full Run-Through (First to End)

This is the complete, ordered sequence to stand up the project from nothing. Each stage lists what it depends on and how to confirm it actually worked — don't skip the verification lines; several bugs in this project's history were silent failures that looked clean until independently checked.

---

## 0. Prerequisites
- Docker Desktop running, with Kubernetes support available
- `kubectl`, `kind`, `envsubst` installed (see main `README.md` for platform-specific setup, including Windows/WSL2 notes)

---

## 1. Docker Compose layer (Kali + Metasploitable)

```bash
docker compose up -d --build
docker compose ps
```
**Verify:** both `kali` and `metasploitable` show `Up`.

```bash
docker compose exec kali nmap -sT metasploitable
```
**Verify:** ports 21, 22, 80 shown open.

---

## 2. Vulnerability scans

```bash
trivy image --scanners vuln cloudsec-lab2-kali:latest > security/trivy/kali-vuln-scan.txt
trivy image --scanners vuln cloudsec-lab2-metasploitable:latest > security/trivy/metasploitable-vuln-scan.txt
```

---

## 3. Create the Kubernetes cluster (kind + Calico)

**Docker Desktop's built-in Kubernetes does not support Calico/NetworkPolicy enforcement — a dedicated `kind` cluster is required.**

```bash
kind create cluster --name cloudsec-lab --config kind-config.yaml
kubectl cluster-info
kubectl get nodes
```
**Verify:** node status `Ready`.

```bash
kubectl config use-context kind-cloudsec-lab
kubectl config current-context
```
**Verify:** prints `kind-cloudsec-lab`.

```bash
kubectl apply -f calico/calico.yaml
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
kubectl get pods -n kube-system | grep calico
```
**Verify:** `calico-node` and `calico-kube-controllers` both `Running`.

---

## 4. Provision a student environment

One command runs all three stages (namespace, RBAC, network policies):

```bash
chmod +x scripts/generate-student-namespace.sh scripts/generate-student-rbac.sh scripts/generate-student-lab.sh

./scripts/generate-student-lab.sh 001
echo "EXIT CODE: $?"
```
**Verify — do not trust the script's own success banner alone:**
```bash
kubectl get ns student-001 --show-labels
kubectl get serviceaccount,role,rolebinding -n student-001
kubectl get networkpolicy -n student-001
```
Expect: namespace with `lab=cloudsec` and `pod-security.kubernetes.io/*` labels; one ServiceAccount, one Role, one RoleBinding; two NetworkPolicies (`default-deny-ingress`, `allow-same-namespace`).

Repeat for each additional student:
```bash
./scripts/generate-student-lab.sh 002
```

---

## 5. Verify isolation with real evidence

**Deploy test pods:**
```bash
kubectl apply -f kubernetes/test-pod.yaml -n student-001
sed 's/name: kali-test/name: kali-test-b/' kubernetes/test-pod.yaml | kubectl apply -n student-002 -f -
kubectl get pods -n student-001 -o wide
kubectl get pods -n student-002 -o wide
```

**Cross-namespace test (expect deny):**
```bash
kubectl exec -it kali-test -n student-001 -- ping -c 3 <student-002-pod-ip>
```
Expect: 100% packet loss.

**Same-namespace test (expect allow) — deploy a second pod in the same namespace first:**
```bash
sed 's/name: kali-test/name: kali-test-b/' kubernetes/test-pod.yaml | kubectl apply -n student-001 -f -
kubectl exec -it kali-test -n student-001 -- ping -c 3 <kali-test-b-same-namespace-ip>
```
Expect: 0% packet loss.

**RBAC isolation:**
```bash
kubectl auth can-i create pods --as=system:serviceaccount:student-001:student-001 -n student-001   # expect: yes
kubectl auth can-i create pods --as=system:serviceaccount:student-001:student-001 -n student-002   # expect: no
```

---

## 6. Known gaps to resolve before treating provisioning as final

- **Backfill NetworkPolicies for any namespace provisioned before the `generate-student-rbac.sh` fix** (affected: `student-004`, `student-005` in this project's history):
  ```bash
  kubectl apply -n student-004 -f kubernetes/network-policies/default-deny.yaml
  kubectl apply -n student-004 -f kubernetes/network-policies/allow-student-internal.yaml
  kubectl get networkpolicy -A
  ```
- **PSA vs. Kali capability conflict is unresolved** — Restricted (and Baseline) PSA both block `NET_RAW`/`NET_ADMIN`, which nmap needs. Current default leaves Kali unable to raw-socket-scan inside Kubernetes. See `docs/session-summary-2026-07-13.md` for the tradeoff and options.
- **Access tokens print to stdout** — fine for local testing, redirect to a file before using with real students:
  ```bash
  kubectl create token student-001 -n student-001 --duration=8h > /tmp/student-001.token
  ```

---

## Full command reference, condensed

```bash
# Compose layer
docker compose up -d --build

# Cluster
kind create cluster --name cloudsec-lab --config kind-config.yaml
kubectl config use-context kind-cloudsec-lab
kubectl apply -f calico/calico.yaml
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s

# Provision students
./scripts/generate-student-lab.sh 001
./scripts/generate-student-lab.sh 002

# Verify
kubectl get networkpolicy -A
kubectl get roles,rolebindings -A | grep student
```