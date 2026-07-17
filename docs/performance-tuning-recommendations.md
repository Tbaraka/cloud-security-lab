# Performance Tuning Recommendations

## Local Kind (this lab)
- Avoid long-running `kubectl -w` watches (causes TLS timeouts under load)
- Prefer ClusterIP + port-forward for Ingress demos
- Keep student ResourceQuota tight (CPU/mem/pods)
- Use HPA on lightweight services (`lab-web`), not heavy Kali images
- Soft pod anti-affinity spreads replicas when multiple nodes exist

## WSL / Docker Desktop
- Allocate ≥8GB RAM to WSL (`.wslconfig`)
- Keep ≥15GB free disk for images + Kind
- Restart `dev-control-plane` if API timeouts persist: `docker restart dev-control-plane`

## Scaling toward 200 students (production)
- Multi-node worker pools with autoscaling node groups
- Separate system nodes for Calico/Ingress/Falco
- Image registry + pre-warmed node caches
- NetworkPolicy CDN deny defaults + allowlists only
- Quotas + LimitRanges required on every namespace
- gVisor RuntimeClass on Linux workers for escape resistance
