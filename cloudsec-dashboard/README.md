# CloudSec Lab Console

A read-only, local, live dashboard for the `kind-cloudsec-lab` cluster. Built for
showing an instructor the real state of the lab during a screen share — not a
mock, not a recording.

## Run it

Requires: Python 3 (stdlib only, no pip install), and `kubectl` already
configured against your `kind-cloudsec-lab` context on this machine.

```bash
cd cloudsec-dashboard
python3 dashboard_server.py
```

Then open **http://127.0.0.1:8787** in your browser. Keep the terminal window
open in the background during the presentation — that's the process serving
the page.

## What it actually does

- Polls `kubectl get`, `kubectl describe`, and `kubectl auth can-i` every 5
  seconds and renders the live result. Nothing is cached or faked.
- Shows every `student-###` namespace on the cluster as a patch-panel slot
  with LED-style indicators for RBAC, PSA, pod status, PVC, NetworkPolicies,
  Ingress, and TLS.
- Clicking a slot opens a detail view plus a raw terminal pane showing the
  *exact* `kubectl` commands run and their unmodified output — point the
  instructor at this if they want proof it isn't staged.

## Safety guarantees (worth stating out loud in the presentation)

- `run_kubectl()` in `dashboard_server.py` is the only function that talks to
  the cluster, and it hard-rejects any verb outside `{get, describe, config,
  auth}`. There is no code path to `apply`, `delete`, `patch`, or `exec`.
- The server refuses to serve live data if your current kubectl context
  isn't `kind-cloudsec-lab` — it will show a red context badge instead of
  silently querying the wrong cluster.
- The HTTP server binds to `127.0.0.1` only. It is not reachable by anyone
  else on a shared network or call, screen-share or not.

## Known limitation

Node allocation parsing (`kubectl describe node`'s "Allocated resources"
table) is regex-based and best-effort — if your kubectl output format
differs, that panel will say "unavailable" rather than showing a wrong
number. Everything else is a direct structured read (`-o json` /
`-o jsonpath`), not text-scraped, so it doesn't share that risk.
