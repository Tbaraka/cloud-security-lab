# Windows Target: Why It Isn't Containerized

This lab does not include a live Windows container or VM in the current
iteration. This is a deliberate scoping decision, not an oversight, and
this document explains the reasoning so it can be evaluated on its
merits.

## Why Windows wasn't containerized

The original task list asks to "convert Kali, Metasploitable, and Windows
VMs to containers **where possible**." For Kali and Metasploitable, this
is straightforward: they are Linux userland with a specific toolset or
vulnerable service set on top, and containers virtualize exactly that
layer well.

Windows does not fit the same model, for three reasons:

1. **Host requirement.** Windows containers require a Windows host running
   the Windows container runtime. They cannot be built or run on macOS or
   Linux, which is the environment this lab was developed on. A
   `Dockerfile` referencing a Windows base image (e.g.
   `mcr.microsoft.com/windows/servercore`) is included for reference only
   and is not part of the working build.

2. **Shared-kernel limitation.** Even on a real Windows host, Windows
   containers share the host OS kernel. This is fine for packaging a
   stateless application, but it does not reproduce what most security
   exercises against "a Windows machine" actually depend on: registry
   behavior, full service-control-manager semantics, driver interaction,
   and OS-level state that differs between a real install and a
   container's shared-kernel view.

3. **No attack surface, even if built.** A minimal Windows Server Core
   container (the smallest available Windows base image) has no GUI, no
   browser, no Office, and none of the client-side or desktop-facing
   surface that most introductory Windows exercises target (RDP,
   client-side payloads, Kerberos/AD-style attacks). Getting the
   container to build would not, by itself, produce something worth
   attacking.

## What Windows would add to this lab

Skipping Windows is a real trade-off, not a free one. A Windows target
would support attack classes that Kali/Metasploitable cannot demonstrate:

- SMB and Active Directory-style attack paths (e.g. Kerberoasting,
  lateral movement in a domain)
- Windows-specific privilege escalation (unquoted service paths, DLL
  hijacking, registry-based persistence) — structurally different from
  Linux SUID/sudo misconfiguration
- GUI-dependent exercises (RDP attacks, client-side payloads opened in an
  actual desktop session)
- A more realistic mixed-OS environment, since most real networks are
  Windows-heavy with Linux infrastructure, not the reverse

This lab, as scoped, only covers Linux-based targets. That is a real gap
against a full enterprise-security curriculum, and is called out here
rather than left implicit.

## The correct way to add a Windows target later

If a Windows target is added in a future iteration, it should be a
**virtual machine**, not a container, for the reasons above. Two options,
in order of fit for this project's Kubernetes-based architecture:

- **KubeVirt** — runs a Windows VM as a native Kubernetes object
  (`VirtualMachineInstance`), so it can be scheduled, namespaced, and
  brought under the same RBAC and network-policy model as the rest of
  this lab's workloads. This is the best fit if Windows needs to be
  orchestrated alongside the containerized Linux targets.
- **Standalone Windows VM** (Hyper-V, VirtualBox, or a cloud provider VM)
  outside the Kubernetes cluster — simpler to stand up, but not
  integrated into the cluster's isolation, RBAC, or autoscaling story,
  so per-student isolation would need to be handled separately.

Note: **Kata Containers is not a Windows solution.** Kata provides
VM-backed isolation for stronger container security, but its guest
kernel support is Linux-only — there is no mainstream Windows guest path.
Kata is used elsewhere in this lab (see `security/kata/README.md`) for
isolating Linux attacker/target containers, not as a Windows option.

## Scope decision for this iteration

This is a **beginner-scope lab**. Standing up a Windows VM (via KubeVirt
or otherwise) is disproportionate to that scope: it introduces a VM
image/licensing dependency, a separate resource and networking model
from the containerized workloads, and a meaningfully larger build than
the rest of this project. The time was prioritized instead on getting
the Linux attacker/target containers working correctly and on the
Kubernetes-level network isolation between students, which are the core
of this lab's stated goal (multi-tenant cloud security), not the
Windows target specifically.

This section is the intended deliverable for the "Windows" line item in
the original task list — a documented, justified architectural decision
in place of a non-functional or misleading containerization attempt.
