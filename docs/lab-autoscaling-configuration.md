# Lab Environment Auto-Scaling Configuration

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
Under load generator traffic, replicas scaled from **1 → 3**.
