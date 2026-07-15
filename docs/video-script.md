# 8-Minute Video Script

| Time | Scene | Show on screen |
|------|-------|----------------|
| 0:00–0:40 | Intro / architecture | Mention Compose + Kind + Calico + Falco |
| 0:40–1:40 | Containers | `docker compose ps`, exec Kali, nmap Meta |
| 1:40–2:40 | Namespaces + quotas | `kubectl get ns,resourcequota` |
| 2:40–3:40 | NetworkPolicy | Before/after cross-ns curl 200 vs 000 |
| 3:40–4:20 | RBAC | `kubectl auth can-i` yes/no |
| 4:20–5:00 | Falco | Trigger nmap + show CyberLab alert |
| 5:00–5:40 | Storage | PVC Bound + `/work/session.txt` |
| 5:40–6:30 | Ingress + TLS/WAF | curl HTTPS/HTTP Host lab.local |
| 6:30–7:20 | HPA | Show scale 1→3 |
| 7:20–8:00 | DR + wrap-up | Mention disaster-recovery.sh and gVisor limitation |

Speak slowly; each demo should already be running before you switch camera to terminal.
