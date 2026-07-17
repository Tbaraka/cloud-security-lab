# gVisor Evaluation

## Why gVisor was selected (design)
gVisor provides an additional isolation layer by intercepting syscalls through a user-space kernel (`runsc`).
Compared with Kata Containers, it typically uses fewer resources, making it attractive for 200+ concurrent student labs.

## Evaluation result on this platform
Attempted:
```bash
docker run --runtime=runsc ...
```
Result:
```text
unknown or invalid runtime name: runsc
```

Docker Desktop (Windows/macOS) does not ship gVisor/`runsc` by default and does not provide a supported one-click install path for Kind nodes.

## Decision
**Deferred / documented limitation** for the beginner local lab.
Isolation for this project is provided by:
- Kind + Calico NetworkPolicies
- Namespaces + RBAC + ResourceQuotas
- Falco runtime monitoring

## Production recommendation
Deploy worker nodes on Linux VMs/cloud instances with `runsc` installed and RuntimeClass:
```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```
