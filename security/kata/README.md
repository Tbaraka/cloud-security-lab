# Kata Containers Evaluation

## What Kata provides
Kata runs each pod/container inside a lightweight VM for stronger isolation than runc.

## Evaluation
Kata was investigated for:
1. Stronger multi-tenant isolation
2. Possible Windows workload hosting

Findings:
- Kata targets **Linux guest** workloads; it does **not** replace Windows VMs for AD/SMB labs.
- Docker Desktop / Kind on Windows does not provide practical Kata hypervisor integration for this beginner lab.

## Decision
**Not implemented** locally. Documented as a production hardening option for bare-metal/cloud Linux clusters with QEMU/Cloud Hypervisor support.

## Windows workloads
Windows attack targets remain **out of scope for containers**. Prefer KubeVirt or standalone VMs.
