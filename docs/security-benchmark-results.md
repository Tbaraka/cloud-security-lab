# Security Benchmark Results

## Image scanning (Trivy)
- Compare routine CVEs vs intentional weak credentials
- Store outputs under `security/trivy/`

## Network isolation
| Test | Before NetworkPolicy | After NetworkPolicy |
|------|----------------------|---------------------|
| Cross-namespace HTTP | 200 | 000 (blocked) |
| Same-namespace HTTP | 200 | 200 |

## Runtime monitoring (Falco)
- Rule: Cyber Lab Suspicious Activity
- Trigger: nmap from kali-lab in student-lab-1
- Result: Warning JSON alert with pod/namespace fields

## Autoscaling
- HPA target CPU 50% (demo temporarily 5%)
- Observed: lab-web replicas 1 → 3 under load

## Ingress / WAF
- Host-based routing: wrong Host → 404; `Host: lab.local` → 200
- ModSecurity + OWASP CRS annotations enabled
