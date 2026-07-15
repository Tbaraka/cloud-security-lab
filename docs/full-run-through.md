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
---

## 7. Ingress, TLS, and WAF (ModSecurity)

**Install ingress-nginx (kind-specific manifest — community project, officially retired March 2026, used here deliberately since this is an isolated lab, not internet-facing):**
```bash
kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```
**Verify:** `kubectl get pods -n ingress-nginx` shows controller `Running`.

**Enable ModSecurity + OWASP CRS (detection-only mode first):**
```bash
kubectl patch configmap ingress-nginx-controller -n ingress-nginx --type merge -p '
data:
  enable-modsecurity: "true"
  enable-owasp-modsecurity-crs: "true"
  allow-snippet-annotations: "true"
  modsecurity-snippet: |
    SecRequestBodyAccess On
    SecAuditEngine RelevantOnly
    SecAuditLogParts ABIJDEFHZ
    SecAuditLog /dev/stdout
    SecAuditLogFormat JSON
    SecAuditLogType Serial
'
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
```
**Verify:** `kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | grep -i modsecurity` → `modsecurity on;`

**Create lab CA + wildcard cert (once):**
```bash
mkdir -p ./ca
openssl genrsa -out ./ca/lab-ca.key 4096
openssl req -x509 -new -nodes -key ./ca/lab-ca.key -sha256 -days 3650 \
  -subj "/CN=cloudsec-lab-ca/O=CloudSec Lab" -out ./ca/lab-ca.crt

WORKDIR=$(mktemp -d)
openssl genrsa -out "$WORKDIR/wildcard.key" 2048
openssl req -new -key "$WORKDIR/wildcard.key" -subj "/CN=*.lab.local" -out "$WORKDIR/wildcard.csr"
echo "subjectAltName = DNS:*.lab.local" > "$WORKDIR/san.ext"
openssl x509 -req -in "$WORKDIR/wildcard.csr" \
  -CA ./ca/lab-ca.crt -CAkey ./ca/lab-ca.key -CAcreateserial \
  -out "$WORKDIR/wildcard.crt" -days 825 -sha256 -extfile "$WORKDIR/san.ext"
cp "$WORKDIR/wildcard.crt" ./ca/wildcard.crt
cp "$WORKDIR/wildcard.key" ./ca/wildcard.key
rm -rf "$WORKDIR"
```
**Verify:** `openssl x509 -in ./ca/wildcard.crt -noout -subject -issuer -dates`

TLS + Ingress + WAF are provisioned automatically per student via `generate-student-lab.sh` (Steps 5 and 8) — no manual per-student cert signing needed.

**Test TLS + WAF (port-forward required first, see Section 8 below):**
```bash
curl -kv --resolve student-011.lab.local:8443:127.0.0.1 https://student-011.lab.local:8443/
curl -k --resolve student-011.lab.local:8443:127.0.0.1 \
  --get "https://student-011.lab.local:8443/" --data-urlencode "id=1' OR '1'='1"
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50 | grep -i "SQL Injection"
```
**Verify:** TLS handshake succeeds with `CN=student-011.lab.local`; SQLi payload returns 200 (detection-only) but the CRS rule `942100` fires in the audit log.

---

## 8. Ingress port-forward (session-persistent helper)

```bash
./scripts/lab-portforward.sh start
./scripts/lab-portforward.sh status
./scripts/lab-portforward.sh stop
```
This is called automatically at the end of `generate-student-lab.sh`, so it's usually already running after provisioning.

---

## 9. Encrypted persistent storage

**One-time: create the LUKS-encrypted volume inside the kind node:**
```bash
docker exec cloudsec-lab-control-plane bash -c "
apt-get update -qq && apt-get install -y -qq cryptsetup >/dev/null
mkdir -p /mnt/encrypted-storage
fallocate -l 5G /mnt/encrypted-disk.img
"
docker exec -it cloudsec-lab-control-plane cryptsetup luksFormat /mnt/encrypted-disk.img
docker exec -it cloudsec-lab-control-plane bash -c "
cryptsetup luksOpen /mnt/encrypted-disk.img student-storage
mkfs.ext4 /dev/mapper/student-storage
mount /dev/mapper/student-storage /mnt/encrypted-storage
"
```
**Verify:** `docker exec cloudsec-lab-control-plane bash -c "mount | grep student-storage; lsblk"` → shows `crypt` type over `loop0`.

**Point local-path-provisioner at it:**
```bash
kubectl patch configmap local-path-config -n local-path-storage --type merge -p '
data:
  config.json: |-
    {"nodePathMap":[{"node":"DEFAULT_PATH_FOR_NON_LISTED_NODES","paths":["/mnt/encrypted-storage"]}]}
'
kubectl rollout restart deployment local-path-provisioner -n local-path-storage
```
Every student's `student-XXX-work` PVC (created automatically in Step 7 of `generate-student-lab.sh`) now lands on this encrypted volume.

**Important caveat:** this LUKS volume must be manually unlocked (`cryptsetup luksOpen`, passphrase required) after any kind-node restart — it does not auto-remount.

---

## 10. Automated backup

```bash
docker exec cloudsec-lab-control-plane mkdir -p /mnt/encrypted-storage-backups

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: student-data-backup
  namespace: kube-system
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: busybox
            command:
            - sh
            - -c
            - |
              TS=\$(date +%Y%m%d-%H%M%S)
              tar czf /backups/student-data-\${TS}.tar.gz -C /source .
              find /backups -name "student-data-*.tar.gz" -mtime +7 -delete
            volumeMounts:
            - name: source
              mountPath: /source
              readOnly: true
            - name: backups
              mountPath: /backups
          volumes:
          - name: source
            hostPath:
              path: /mnt/encrypted-storage
          - name: backups
            hostPath:
              path: /mnt/encrypted-storage-backups
EOF
```
**Verify (manual trigger, don't wait for 2am):**
```bash
kubectl create job --from=cronjob/student-data-backup manual-backup-test -n kube-system
kubectl wait --for=condition=complete job/manual-backup-test -n kube-system --timeout=60s
docker exec cloudsec-lab-control-plane ls -lh /mnt/encrypted-storage-backups
```
**Known gap:** backups live on the same encrypted disk as source data — violates 3-2-1 backup principle. Not yet copied off-disk.

---

## 11. Falco (compromise detection)

```bash
brew install helm
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set tty=true
```
**Verify:** `kubectl get pods -n falco` → `1/2` or `2/2 Running`, no `CrashLoopBackOff`. **Always confirm `kubectl config current-context` is `kind-cloudsec-lab` first** — this project has hit the wrong-cluster bug twice.

**Custom rules (scoped to lab-specific compromise signals, not stock "shell spawned" noise):**
```bash
cat > /tmp/falco-custom-rules.yaml << 'EOF'
customRules:
  lab-rules.yaml: |-
    - macro: kali_namespace
      condition: k8s.ns.name startswith "student-" and not k8s.ns.name endswith "-target"
    - macro: target_namespace
      condition: k8s.ns.name endswith "-target"
    - rule: Lab Container Breakout Attempt
      desc: Process attempted to access host filesystem or container runtime socket from within a lab pod
      condition: >
        evt.type in (open, openat, openat2) and
        (kali_namespace or target_namespace) and
        (fd.name startswith /var/run/docker.sock or
         fd.name startswith /var/run/containerd or
         fd.name startswith /proc/1/root or
         fd.name startswith /host)
      output: "Possible container breakout in lab pod (user=%user.name command=%proc.cmdline container=%container.name ns=%k8s.ns.name file=%fd.name)"
      priority: CRITICAL
      tags: [lab, breakout]
    - rule: Unexpected Outbound Connection From Target
      desc: Metasploitable target pod initiated an outbound connection
      condition: >
        evt.type = connect and
        target_namespace and
        outbound and
        not fd.sip in (allowed_target_egress_ips)
      output: "Target pod made outbound connection (container=%container.name ns=%k8s.ns.name dest=%fd.rip:%fd.rport)"
      priority: WARNING
      tags: [lab, target-egress]
    - list: allowed_target_egress_ips
      items: []
    - rule: Unexpected Privilege Escalation In Target
      desc: A process gained root/setuid in the target namespace outside the pod's own defined entrypoint
      condition: >
        evt.type = execve and
        target_namespace and
        proc.is_exe_upper_layer=true and
        proc.vpid != 1
      output: "Unexpected privileged exec in target (user=%user.name cmdline=%proc.cmdline container=%container.name)"
      priority: WARNING
      tags: [lab, privesc]
EOF
helm upgrade falco falcosecurity/falco --namespace falco --reuse-values -f /tmp/falco-custom-rules.yaml
```
**Verify no errors (not just warnings):**
```bash
kubectl rollout status daemonset/falco -n falco
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i "error\|invalid"
```

**Note `evt.dir` is deprecated** — do not add `evt.dir = <` / `evt.dir = >` to any condition; it causes a hard compile error and crash loop on current Falco versions.

**Known bug:** "Lab Container Breakout Attempt" does not currently fire despite confirmed-successful `/proc/1/root` reads. Unresolved. "Unexpected Outbound Connection From Target" is proven working.

---

## 12. Snapshot management & clean environment deployment

**One-time: snapshot/golden directories:**
```bash
docker exec cloudsec-lab-control-plane mkdir -p /mnt/encrypted-storage-snapshots
docker exec cloudsec-lab-control-plane mkdir -p /mnt/encrypted-storage-golden
```

**On-demand snapshot of a student's workspace:**
```bash
./scripts/snapshot-student.sh <student-id>
```

**Restore a specific snapshot:**
```bash
./scripts/restore-student-snapshot.sh <student-id> <snapshot-filename>.tar.gz
```

**Build/update the golden (clean starter) snapshot — must be built with macOS tar artifacts excluded:**
```bash
WORKDIR=$(mktemp -d)
cat > "$WORKDIR/.golden-info" << EOF
golden_snapshot=true
created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
description=Clean starter workspace, no scan output or student files
EOF
chmod 0777 "$WORKDIR"
COPYFILE_DISABLE=1 tar czf /tmp/golden-workspace.tar.gz --exclude='.' --exclude='._*' -C "$WORKDIR" .golden-info
docker cp /tmp/golden-workspace.tar.gz cloudsec-lab-control-plane:/mnt/encrypted-storage-golden/golden-workspace.tar.gz
rm -rf "$WORKDIR"
```

**Quick deployment of a clean environment (new student):**
```bash
./scripts/generate-student-lab.sh <student-id>
./scripts/load-golden-snapshot.sh <student-id>
```

**Full clean redeploy of an existing (possibly compromised) student — destroys and rebuilds both namespaces, requires typed confirmation:**
```bash
./scripts/redeploy-clean-student.sh <student-id>
```

**Check environment status, including whether golden was loaded:**
```bash
./scripts/show-student-env.sh <student-id>
```

**Known permissions gotcha:** `local-path-provisioner`'s `setup` script creates new PVC directories as `0777`, but any directory created before the encrypted-storage path patch may be stuck at `0755` (root-only write). If a student can't write to their workspace, check with:
```bash
docker exec cloudsec-lab-control-plane ls -la /mnt/encrypted-storage/ | grep student-XXX
```
and `chmod 0777` the specific directory if needed.