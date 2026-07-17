# Pod Security & Policy Controls (PSP / OPA Substitute)

## Why PodSecurityPolicy was not used
Kubernetes **PodSecurityPolicy (PSP)** was deprecated in v1.21 and removed in v1.25+.
This lab runs Kubernetes **v1.31** on Kind, so PSP is unavailable.

## Controls used instead

| Control | Purpose in this lab |
|---------|---------------------|
| **RBAC** (`student-sa` Role/RoleBinding) | Students only manage resources in their own namespace |
| **ResourceQuota** | Cap CPU/memory/pods per student |
| **Calico NetworkPolicy** | Tenant isolation (default deny + allowlists) |
| **Falco** | Runtime detection of suspicious syscalls/tools |
| **Ingress ModSecurity / OWASP CRS** | Edge WAF for HTTP attacks |
| **Pod Security Standards (restricted labels optional)** | API-level hardening path for production |

## OPA / Gatekeeper
Full OPA Gatekeeper was not deployed on the beginner Kind single-node lab due to resource limits.
Equivalent policy intent is enforced via RBAC + NetworkPolicy + quotas + Falco.

### Example future Gatekeeper constraint (documented, not required to apply)
```yaml
# Deny privileged pods in student namespaces
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: deny-privileged-students
spec:
  match:
    namespaces: ["student-lab-*"]
```

## Verification commands
```bash
kubectl auth can-i create pods --as=system:serviceaccount:student-lab-1:student-sa -n student-lab-1
kubectl auth can-i create pods --as=system:serviceaccount:student-lab-1:student-sa -n student-lab-2
kubectl get networkpolicy -n student-lab-1
kubectl get pods -n falco
```
