# Lab Environment Auto-Scaling Configuration

**Status: Verified working (2026-07-19), on a real multi-node cluster, against a real workload.**

This supersedes an earlier version of this doc, which described an isolated
single-namespace POC (`lab-web` in `student-lab-1`) never wired into the
real per-student pipeline, with an unverified "1→3" scaling claim
contradicted by live cluster state at the time. That POC no longer exists.
Everything below was directly observed and verified against the actual
running cluster.

## Why the target is ingress-nginx-controller, not student pods

Each student's Kali/Metasploitable environment is a pair of standalone,
stateful `Pod` objects (not a `Deployment`/`ReplicaSet`), each with its own
PVC. There is nothing to horizontally scale per student — a student's
attacker box is not a replicated, interchangeable unit. HPA requires a
scalable resource (Deployment/ReplicaSet/StatefulSet), so the legitimate
target for "scale lab environments based on student demand" is the shared
component all students' traffic passes through: `ingress-nginx-controller`.

## Cluster prerequisite: multi-node

The cluster was rebuilt from single-node to 2 nodes
(`kind/kind-config.yaml`: 1 control-plane + 1 worker) specifically to make
this deliverable meaningful — on a single node, "scaling" a Deployment just
stacks replicas on the same physical host with no real distribution
benefit, and pod anti-affinity has nothing to enforce.

Rebuilding required reinstalling: Calico (manifest now committed at
`calico/calico.yaml` — it was previously undocumented and not present in
the repo despite being referenced in `docs/full-run-through.md`),
ingress-nginx, Falco, and metrics-server, plus re-provisioning all student
namespaces. Encrypted storage and snapshot data do not survive a cluster
rebuild by default (see note below) and were manually preserved via
`docker cp` before deletion.

## metrics-server

Required for any CPU-based HPA decision and was not previously installed.
Installed via the standard manifest with `--kubelet-insecure-tls` (required
for kind's self-signed kubelet certs):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

Verify: `kubectl top nodes` returns real CPU/memory figures, not an error.

## HPA object

```yaml
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
```

## Known ceiling: maxReplicas is capped at node count, not chosen arbitrarily

The kind-specific ingress-nginx manifest
(`deploy/static/provider/kind/deploy.yaml`) binds the controller pod
directly to node ports 80/443 via `hostPort`, rather than a cloud
LoadBalancer Service. This means **only one ingress-nginx pod can ever
schedule per node** — a second replica on the same node fails with
`0/N nodes are available: N node(s) didn't have free ports for the
requested pod ports`. This was hit directly during testing (an initial
`maxReplicas: 4` on a 2-node cluster caused stuck `Pending` pods) and
corrected to `maxReplicas: 2` to match the real constraint.

**This is a hard architectural ceiling of this ingress approach, not a
config oversight.** True higher-replica scaling would require either more
nodes, or switching from the kind-specific hostPort-based manifest to a
different ingress deployment method (e.g. a NodePort/LoadBalancer Service
instead of hostPort) — out of scope for this lab.

## Pod anti-affinity

Applied as `preferredDuringSchedulingIgnoredDuringExecution` (soft, not
hard — a hard requirement combined with the 2-replica hostPort ceiling
above would make scheduling brittle) on `app.kubernetes.io/component:
controller`, topology key `kubernetes.io/hostname`:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app.kubernetes.io/component: controller
        topologyKey: kubernetes.io/hostname
```

## Verified result (2026-07-19)

```bash
kubectl get hpa -n ingress-nginx
kubectl get pods -n ingress-nginx -o wide
```

- Real load generated via `curl` flood from a student Kali pod against the
  live per-student ingress path.
- CPU utilization observed climbing to 55% (target: 30%).
- HPA scaled the deployment from 1 → 2 replicas in direct response — the
  actual `kubectl get hpa -w` transcript is preserved in session notes.
- After the anti-affinity rule was applied and the deployment rolled, both
  replicas were confirmed running on the two different nodes
  (`cloudsec-lab-control-plane` and `cloudsec-lab-worker`) — not scheduler
  coincidence, since the rule was live at rollout time.
- CPU fell back below target after load stopped; replicas remained at 2
  during the HPA's stabilization window (expected, correct behavior) before
  eventually settling back down.

## Encrypted storage / snapshot durability caveat (found during this rebuild)

The LUKS-encrypted volume and all snapshot files live entirely inside the
kind node's Docker-managed volume, with no host bind-mount. A cluster
rebuild (`kind delete cluster`) permanently destroys this data unless
manually copied off first (`docker cp`) — there is currently no script in
this repo that does this automatically. This should be treated as a
real gap in the "automated backup" / "encrypted persistent storage"
deliverables, not just an autoscaling side-note.
