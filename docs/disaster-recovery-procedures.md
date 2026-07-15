# Disaster Recovery Procedures

## Scenarios
1. Student environment compromised
2. Accidental deletion of lab pods
3. Need to restore student work files

## Quick recovery (clean environment)
```bash
bash ./scripts/disaster-recovery.sh student-lab-1
```
This will:
1. Auto-backup current namespace
2. Delete the namespace
3. Recreate namespace + quota + RBAC
4. Redeploy Kali/Metasploitable/storage/policies/ingress
5. Re-issue TLS secret

## Backup only
```bash
bash ./scripts/backup-student-lab.sh student-lab-1
```
Creates `backups/student-lab-1-<timestamp>/` with manifests + `/work` tar.

## Restore work data after DR
```bash
bash ./scripts/disaster-recovery.sh student-lab-1 backups/student-lab-1-YYYYMMDD-HHMMSS
```

## Snapshot management (local Kind)
- Manifest snapshots: `backups/*`
- Volume data: `work-data.tar`
- Production: use Velero + cloud disk snapshots

## Compromise response checklist
1. Isolate: confirm NetworkPolicies still deny cross-tenant traffic
2. Capture Falco alerts for evidence
3. Run `disaster-recovery.sh` for clean redeploy
4. Re-issue TLS and notify student
5. Review Falco logs for recurrence
