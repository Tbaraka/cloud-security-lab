# Cloud Security Lab — Full Run-Through (First to End)

This is the complete, ordered sequence to stand up the project from nothing. Each stage lists what it depends on and how to confirm it actually worked — don't skip the verification lines; several bugs in this project's history were silent failures that looked clean until independently checked.

---

## 0. Prerequisites
- Docker Desktop running, with Kubernetes support available
- `kubectl`, `kind`, `helm`, `envsubst` installed

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
trivy image --scanners vuln kali-lab:latest > security/trivy/kali-vuln-scan.txt
trivy image --scanners vuln metasploitable-lab:latest > security/trivy/metasploitable-vuln-scan.txt
```
No CI pipeline exists — this is a manual step, re-run before each build cycle.

---

## 3. Create the Kubernetes cluster (kind + Calico)

**Docker Desktop's built-in Kubernetes does not support Calico/NetworkPolicy enforcement — a dedicated `kind` cluster is required.**

Cluster is 2 nodes (1 control-plane, 1 worker) — required for autoscaling and pod anti-affinity to mean anything.

```bash
kind create cluster --name cloudsec-lab --config kind/kind-config.yaml
kubectl config use-context kind-cloudsec-lab
kubectl config current-context
kubectl get nodes
```
**Verify:** both nodes `Ready`, context prints `kind-cloudsec-lab`.

```bash
kubectl apply -f calico/calico.yaml
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
kubectl get pods -n kube-system | grep calico
```
**Verify:** `calico-node` (one per node) and `calico-kube-controllers` all `Running`.

---

## 4. Provision a student environment

```bash
chmod +x scripts/*.sh
bash scripts/generate-student-lab.sh 009
echo "EXIT CODE: $?"
```
Single orchestrator — runs namespace, RBAC, network policies, target pod, TLS, storage, Kali pod, ingress, in order.

**Verify — do not trust the script's own success banner alone:**
```bash
kubectl get ns student-009 --show-labels
kubectl get serviceaccount,role,rolebinding -n student-009
kubectl get networkpolicy -n student-009
kubectl get pods -n student-009
kubectl get pods -n student-009-target
```
Expect: namespace with `lab=cloudsec` and `pod-security.kubernetes.io/*` labels; ServiceAccount, Role, RoleBinding present; 3 NetworkPolicies; `kali-attacker` and `target-metasploitable` both `Running`.

Repeat for each additional student:
```bash
bash scripts/generate-student-lab.sh 010
```

---

## 5. Verify isolation with real evidence

**Cross-namespace test (expect deny):**
```bash
kubectl get pod kali-attacker -n student-010 -o jsonpath='{.status.podIP}'
kubectl exec -it kali-attacker -n student-009 -- ping -c 3 <student-010-pod-ip>
```
Expect: 100% packet loss.

**Same-namespace test (expect allow):**
```bash
kubectl exec -it kali-attacker -n student-009 -- ping -c 3 <target-metasploitable-ip-same-student>
```
Expect: 0% packet loss.

**RBAC isolation:**
```bash
kubectl auth can-i get pods --as=system:serviceaccount:student-009:student-009 -n student-009   # expect: yes
kubectl auth can-i get pods --as=system:serviceaccount:student-009:student-009 -n student-010   # expect: no
kubectl auth can-i create configmaps --as=system:serviceaccount:student-009:student-009 -n student-009   # expect: no
```

---

## 6. Ingress, TLS, and WAF (ModSecurity)

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
kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=120s
```

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
TLS + Ingress + WAF are provisioned automatically per student via `generate-student-lab.sh` — no manual per-student cert signing needed.

**Test TLS + WAF:**
```bash
curl -kv --resolve student-009.lab.local:8443:127.0.0.1 https://student-009.lab.local:8443/
curl -k --resolve student-009.lab.local:8443:127.0.0.1 \
  --get "https://student-009.lab.local:8443/" --data-urlencode "id=1' OR '1'='1"
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50 | grep -i "SQL Injection"
```
**Verify:** TLS handshake succeeds; SQLi payload returns 200 (detection-only), CRS rule `942100` fires in audit log.

---

## 7. Ingress port-forward

```bash
./scripts/lab-portforward.sh start
./scripts/lab-portforward.sh status
```
Auto-invoked at the end of `generate-student-lab.sh`.

---

## 8. Encrypted persistent storage

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
**Verify:** `docker exec cloudsec-lab-control-plane lsblk` → `crypt` type over `loop0`.

**Point local-path-provisioner at it:**
```bash
kubectl patch configmap local-path-config -n local-path-storage --type merge -p '
data:
  config.json: |-
    {"nodePathMap":[{"node":"DEFAULT_PATH_FOR_NON_LISTED_NODES","paths":["/mnt/encrypted-storage"]}]}
'
kubectl rollout restart deployment local-path-provisioner -n local-path-storage
```

**Known gap — data does not survive a cluster rebuild:** the encrypted volume and all snapshots live inside the kind node's Docker-managed filesystem with no host bind-mount. `kind delete cluster` destroys all of it. No script automates preservation; do this manually before any rebuild:
```bash
docker cp cloudsec-lab-control-plane:/mnt/encrypted-storage-snapshots/. ./_preserved-node-data/encrypted-storage-snapshots/
docker cp cloudsec-lab-control-plane:/mnt/encrypted-storage/. ./_preserved-node-data/encrypted-storage/
```

---

## 9. Automated backup

```bash
bash scripts/backup-student-lab.sh student-009
```
Creates `backups/student-009-<timestamp>/` with manifests and `work-data.tar`.

**Verify:**
```bash
LATEST=$(ls -td backups/student-009-* | head -1)
tar -tvf "$LATEST/work-data.tar"
```

---

## 10. Disaster recovery

```bash
LATEST=$(ls -td backups/student-009-* | head -1)
bash scripts/disaster-recovery.sh student-009 "$LATEST"
echo "DR exit code: $?"
```
Auto-backs up, deletes both namespaces, redeploys via `generate-student-lab.sh`, restores workspace from the given backup.

**Verify:**
```bash
kubectl exec -n student-009 kali-attacker -- cat /home/kali/workspace/<restored-file>
```
Exit code must be `0` and file content must match — do not trust script output alone.

---

## 11. Falco (compromise detection)

```bash
bash scripts/install-falco.sh
```
Wraps `helm upgrade --install falco falcosecurity/falco --namespace falco --values monitoring/falco/values.yaml`.

**Verify context first — always:**
```bash
kubectl config current-context
```

**Verify rules actually deployed match the repo (Helm releases can drift):**
```bash
kubectl exec -n falco $(kubectl get pod -n falco -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].metadata.name}') -c falco -- cat /etc/falco/rules.d/cyber-lab.yaml
```
Expect three rules: `Cyber Lab Suspicious Activity` (WARNING), `Cyber Lab Read Shadow` (WARNING), `Lab Container Breakout Attempt` (CRITICAL). If the live pod's rules don't match `monitoring/falco/values.yaml`, re-run `install-falco.sh` — the release has drifted and needs re-syncing.

**Trigger and confirm alerts fire:**
```bash
bash scripts/demo-falco-alert.sh 009
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50 | grep -i cyberlab
```

**Note:** `evt.dir` is deprecated — do not use `evt.dir = <` / `evt.dir = >` in any condition; causes a hard compile error and crash loop.

---

## 12. Automated recovery on compromise

```bash
bash scripts/falco-auto-responder.sh
```
Dry-run by default — watches Falco logs, prints what it would do on a CRITICAL alert. Add `--live` to actually trigger `disaster-recovery.sh` automatically.

```bash
bash scripts/falco-auto-responder.sh --live
```

**Trigger a real CRITICAL alert to test (in a second terminal):**
```bash
kubectl -n student-009 exec kali-attacker -- sh -c 'cat /proc/1/root/etc/hostname 2>&1'
```
**Verify:** responder terminal shows the CRITICAL alert detected and DR triggered; check `logs/auto-dr-student-009-*.log` for the full DR transcript; confirm pod healthy afterward with `kubectl get pods -n student-009`.

---

## 13. Snapshot management & clean environment deployment

```bash
bash scripts/snapshot-student.sh 009
bash scripts/restore-student-snapshot.sh 009 <snapshot-filename>.tar.gz
```

**Quick deployment of a clean environment (new student):**
```bash
bash scripts/generate-student-lab.sh <student-id>
bash scripts/load-golden-snapshot.sh <student-id>
```

**Full clean redeploy of an existing student (destroys and rebuilds both namespaces, requires typed confirmation):**
```bash
bash scripts/redeploy-clean-student.sh <student-id>
```

**Check status:**
```bash
bash scripts/show-student-env.sh <student-id>
```

---

## 14. Autoscaling and pod anti-affinity

**Install metrics-server (required for HPA):**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl top nodes
```

**HPA on the ingress controller — not student pods (student pods are non-scalable, stateful Pod objects, not Deployments):**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ingress-nginx-controller-hpa
  namespace: ingress-nginx
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ingress-nginx-controller
  minReplicas: 1
  maxReplicas: 2
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 30
EOF
```
`maxReplicas: 2` matches node count — kind's ingress-nginx manifest binds `hostPort`, so only one replica can schedule per node. Do not set this higher without more nodes.

**Pod anti-affinity (soft):**
```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=strategic -p '
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/component: controller
              topologyKey: kubernetes.io/hostname
'
```

**Verify with real load:**
```bash
kubectl -n student-009 exec kali-attacker -- sh -c 'for i in $(seq 1 2000); do curl -sk --resolve student-009.lab.local:8443:127.0.0.1 https://student-009.lab.local:8443/ -o /dev/null & done; wait' &
kubectl get hpa -n ingress-nginx -w
```
Expect replicas to scale 1 → 2 under load. Then confirm distribution:
```bash
kubectl get pods -n ingress-nginx -o wide
```
Expect the two replicas on different `NODE` values.

---

## 15. Monitoring (Prometheus/Grafana) — known limitation

Full `kube-prometheus-stack` was attempted and reverted. It repeatedly overloaded the control plane on a single-Mac Docker Desktop setup already running Calico, Falco (both nodes), ingress-nginx, and metrics-server — caused sustained `TLS handshake timeout` errors and required a control-plane container restart to recover:
```bash
docker restart cloudsec-lab-control-plane
```
If pursued further, use a trimmed install (disable Alertmanager, cap resource requests) rather than the full default chart:
```bash
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set alertmanager.enabled=false \
  --set prometheus.prometheusSpec.resources.requests.cpu=100m \
  --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
  --set grafana.resources.requests.cpu=50m \
  --set grafana.resources.requests.memory=128Mi
```

---

```