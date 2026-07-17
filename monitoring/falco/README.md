# Falco Runtime Security Monitoring

## What Falco does
Falco detects suspicious runtime behavior in containers and on the host
(shells in containers, sensitive file access, privilege escalation, etc.).

## Install
```bash
cd ~/cloud-security-lab
bash ./scripts/install-falco.sh
```

## Watch alerts
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

## Demo (generate evidence for report)
```bash
# Terminal 1: stream Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Terminal 2: trigger activity
bash ./scripts/demo-falco-alert.sh student-lab-1
```

## Expected detections
- Terminal shell in container
- Reads of sensitive files (e.g. /etc/shadow)
- Unexpected process launches inside lab pods

## Notes for Kind + Docker Desktop
- Uses `driver.kind=modern_ebpf` (no out-of-tree kernel module)
- Requires privileged Falco DaemonSet pods
- Works with the `kind-dev` cluster used for Calico/NetworkPolicy demos
