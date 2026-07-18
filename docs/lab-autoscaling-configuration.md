# Lab Environment Auto-Scaling Configuration (POC — NOT integrated into per-student pipeline)

## HPA object
- Deployment: `lab-web` in `student-lab-1`
- Min replicas: 1
- Max replicas: 3
- Metric: CPU utilization target **50%** of requests
- Manifest: `kubernetes/ingress/lab-web-ingress-hpa.yaml`

## Soft pod anti-affinity
`preferredDuringSchedulingIgnoredDuringExecution` on `app=lab-web` with topology `kubernetes.io/hostname`.
On single-node Kind this is best-effort; on multi-node clusters replicas spread across nodes for resilience/security.

## Verification
```bash
kubectl get hpa lab-web-hpa -n student-lab-1
kubectl get deploy lab-web -n student-lab-1
kubectl get pods -n student-lab-1 -l app=lab-web -o wide
```

## Observed result
Under load generator traffic in an isolated POC test (namespace `student-lab-1`, unrelated to the real per-student `student-XXX` pipeline), replicas were observed scaling from **1 → 3**. This has NOT been reproduced against the live per-student architecture — `kubectl get hpa -A` currently shows no HPA objects. Autoscaling is NOT a working feature of the deployed lab.
