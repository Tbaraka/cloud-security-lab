# Cloud Security Lab — Progress Report (Updated)

**Project:** Cloud-based cybersecurity training lab (containerized attacker/target + multi-tenant Kind platform)  
**Scope:** Beginner-level, single-developer, local environment  
**Host:** Windows + WSL2 Ubuntu + Docker Desktop  
**Kubernetes:** Kind cluster `dev` (context `kind-dev`), Calico CNI  
**Status:** Core platform complete. Documentation and TLS/DR automation added.

## Environment (current truth)
- Docker Compose for image bring-up and tool validation
- Kind (not Docker Desktop Kubernetes) for orchestration
- Calico for NetworkPolicy enforcement
- Falco for runtime security monitoring
- NGINX Ingress + ModSecurity/OWASP CRS + TLS secret termination
- PVC storage + HPA autoscaling + soft anti-affinity

## Completed
- Kali + Metasploitable containers; Windows documented out-of-scope
- Trivy scanning approach (security/trivy)
- gVisor/Kata evaluated and documented as deferred limitations
- Namespaces + ResourceQuota automation
- RBAC student least privilege
- Calico NetworkPolicies + isolation proofs
- Ingress + WAF annotations; TLS CA + per-lab Secret
- PersistentVolumeClaim student work + Secret mount
- Backup + disaster-recovery scripts
- Falco with custom CyberLab rules
- HPA scale demonstration (1→3)
- Soft pod anti-affinity on lab-web
- PSP/OPA substitute documentation (PSP removed in modern K8s)

## Remaining for submission packaging
- Assemble screenshots into `docs/screenshots/`
- Record 8-minute demonstration video (see `docs/video-script.md`)
- Optional: Prometheus/Grafana (nice-to-have)

## Note on earlier draft
Earlier progress text referring to macOS Docker Desktop Kubernetes and “NetworkPolicies not yet applied” is **obsolete** and superseded by this Kind + Calico implementation.
