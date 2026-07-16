# Network Isolation Strategy

## Goals
Isolate 200+ concurrent student environments so one student cannot reach another student's lab pods.

## Layers
1. **Namespace per student** — organizational + RBAC boundary
2. **ResourceQuota** — prevent noisy-neighbor resource exhaustion
3. **Calico NetworkPolicy**
   - `default-deny-all` (Ingress + Egress)
   - `allow-same-namespace` for intra-lab traffic
   - `allow-dns` for CoreDNS
   - `allow-kali-to-metasploitable` / `allow-metasploitable-from-kali` for pentest path
   - `allow-from-ingress-nginx` for platform Ingress only to `lab-web`
4. **Ingress host routing** (`lab.local`) + ModSecurity WAF

## Evidence
- Before policies: cross-namespace HTTP **200**
- After policies: cross-namespace HTTP **000**; same-namespace HTTP **200**

## Scaling to 200 students
```bash
for i in $(seq 1 200); do
  bash ./scripts/generate-student-namespace.sh student-lab-$i
  bash ./scripts/generate-student-rbac.sh student-lab-$i
  bash ./scripts/generate-student-lab.sh $i
done
```
