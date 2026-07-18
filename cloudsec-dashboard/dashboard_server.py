#!/usr/bin/env python3
"""
CloudSec Lab Console — read-only live dashboard for the cloudsec-lab kind cluster.

SAFETY MODEL (read this before changing anything):
  - Every kubectl call goes through run_kubectl() below.
  - run_kubectl() hard-rejects any verb that is not in ALLOWED_VERBS.
    "apply", "delete", "patch", "replace", "create", "exec", "cp" etc. are
    NOT in that set and CANNOT be added by a request — they simply aren't
    reachable code paths. This app cannot mutate the cluster.
  - The server refuses to serve live data if the current kubectl context is
    not REQUIRED_CONTEXT, so it can never accidentally point at the wrong
    cluster.
  - The HTTP server binds to 127.0.0.1 only. It is not reachable from
    anywhere else on the network, including during a screen share — only
    your own machine can hit it.

Run:
    python3 dashboard_server.py
Then open:
    http://127.0.0.1:8787
"""

import json
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

REQUIRED_CONTEXT = "kind-cloudsec-lab"
BIND_HOST = "127.0.0.1"
BIND_PORT = 8787
STATIC_DIR = Path(__file__).parent / "static"

# The only kubectl verbs this process will ever execute. Read-only, by design.
ALLOWED_VERBS = {"get", "describe", "config", "auth"}

STUDENT_ID_RE = re.compile(r"^[0-9]{3}$")
NAMESPACE_RE = re.compile(r"^student-([0-9]{3})$")


class KubectlError(Exception):
    pass


def run_kubectl(args, timeout=8):
    """The only place this process talks to the cluster. Verb-locked."""
    if not args or args[0] not in ALLOWED_VERBS:
        raise KubectlError(f"refused: '{args[0] if args else ''}' is not a read-only verb")
    cmd = ["kubectl"] + args
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, check=False
        )
    except subprocess.TimeoutExpired:
        raise KubectlError(f"timeout running: {' '.join(cmd)}")
    if result.returncode != 0:
        raise KubectlError(result.stderr.strip() or f"kubectl exited {result.returncode}")
    return result.stdout


def current_context():
    try:
        return run_kubectl(["config", "current-context"]).strip()
    except KubectlError:
        return None


def guard_context():
    ctx = current_context()
    if ctx != REQUIRED_CONTEXT:
        raise KubectlError(
            f"current context is '{ctx}', expected '{REQUIRED_CONTEXT}' — "
            f"refusing to query. Run: kubectl config use-context {REQUIRED_CONTEXT}"
        )
    return ctx


def list_student_namespaces():
    raw = run_kubectl(["get", "ns", "-o", "json"])
    data = json.loads(raw)
    ids = []
    for item in data.get("items", []):
        m = NAMESPACE_RE.match(item["metadata"]["name"])
        if m:
            ids.append(m.group(1))
    return sorted(ids)


def phase_of(kind, name, namespace):
    try:
        out = run_kubectl(
            ["get", kind, name, "-n", namespace, "-o", "jsonpath={.status.phase}"]
        )
        return out.strip() or "Unknown"
    except KubectlError:
        return "Missing"


def count_networkpolicies(namespace):
    try:
        out = run_kubectl(["get", "networkpolicy", "-n", namespace, "-o", "json"])
        return len(json.loads(out).get("items", []))
    except KubectlError:
        return 0


def exists(kind, name, namespace):
    try:
        out = run_kubectl(["get", kind, name, "-n", namespace, "--ignore-not-found"])
        return bool(out.strip())
    except KubectlError:
        return False


def can_i(verb, resource, namespace, as_sa):
    try:
        out = run_kubectl(
            [
                "auth", "can-i", verb, resource,
                f"--as=system:serviceaccount:{namespace}:{as_sa}",
                "-n", namespace,
            ]
        )
        return out.strip() == "yes"
    except KubectlError:
        return False


def student_summary(sid):
    ns = f"student-{sid}"
    tns = f"{ns}-target"
    sa = f"student-{sid}"

    psa = "unknown"
    try:
        psa = run_kubectl(
            ["get", "namespace", ns, "-o",
             "jsonpath={.metadata.labels.pod-security\\.kubernetes\\.io/enforce}"]
        ).strip() or "unset"
    except KubectlError:
        psa = "missing"

    rbac_ok = (
        exists("serviceaccount", sa, ns)
        and exists("role", "student-role", ns)
        and exists("rolebinding", f"{sa}-binding", ns)
    )

    return {
        "id": sid,
        "namespace": ns,
        "psa": psa,
        "rbac_objects": rbac_ok,
        "rbac_exec_allowed": can_i("create", "pods/exec", ns, sa),
        "rbac_configmaps_denied": not can_i("create", "configmaps", ns, sa),
        "rbac_deployments_denied": not can_i("create", "deployments", ns, sa),
        "target_pod": phase_of("pod", "target-metasploitable", tns),
        "kali_pod": phase_of("pod", "kali-attacker", ns),
        "pvc": phase_of("pvc", f"student-{sid}-work", ns),
        "netpol_count": count_networkpolicies(ns),
        "target_netpol_count": count_networkpolicies(tns),
        "ingress": exists("ingress", f"student-{sid}-ingress", tns),
        "tls": exists("secret", f"student-{sid}-tls", tns),
    }


def student_raw(sid):
    """The transparency pane: exact commands + exact output, unmodified."""
    ns = f"student-{sid}"
    tns = f"{ns}-target"
    commands = [
        ["get", "pods", "-n", ns],
        ["get", "pods", "-n", tns],
        ["get", "pvc", "-n", ns],
        ["get", "networkpolicy", "-n", ns],
    ]
    blocks = []
    for args in commands:
        cmd_str = "kubectl " + " ".join(args)
        try:
            out = run_kubectl(args)
        except KubectlError as e:
            out = f"ERROR: {e}"
        blocks.append({"command": cmd_str, "output": out})
    return blocks


def node_allocation():
    """Best-effort parse of `kubectl describe node`'s Allocated resources table."""
    try:
        raw = run_kubectl(["describe", "node"])
    except KubectlError as e:
        return {"available": False, "reason": str(e)}

    cpu_req = cpu_lim = mem_req = mem_lim = None
    for line in raw.splitlines():
        line = line.strip()
        m = re.match(r"^cpu\s+\S+\s*\((\d+)%\)\s+\S+\s*\((\d+)%\)", line)
        if m:
            cpu_req, cpu_lim = int(m.group(1)), int(m.group(2))
        m = re.match(r"^memory\s+\S+\s*\((\d+)%\)\s+\S+\s*\((\d+)%\)", line)
        if m:
            mem_req, mem_lim = int(m.group(1)), int(m.group(2))

    if mem_req is None:
        return {"available": False, "reason": "could not parse 'Allocated resources' section"}

    return {
        "available": True,
        "cpu_requests_pct": cpu_req,
        "cpu_limits_pct": cpu_lim,
        "mem_requests_pct": mem_req,
        "mem_limits_pct": mem_lim,
    }


def build_state():
    ctx = guard_context()
    ids = list_student_namespaces()
    students = [student_summary(sid) for sid in ids]
    return {
        "context": ctx,
        "node": node_allocation(),
        "students": students,
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # keep the terminal quiet during a live presentation

    def _json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/state":
            try:
                self._json(build_state())
            except KubectlError as e:
                self._json({"error": str(e)}, status=503)
            return

        if path.startswith("/api/student/"):
            sid = path.rsplit("/", 1)[-1]
            if not STUDENT_ID_RE.match(sid):
                self._json({"error": "invalid student id"}, status=400)
                return
            try:
                guard_context()
                self._json({"raw": student_raw(sid)})
            except KubectlError as e:
                self._json({"error": str(e)}, status=503)
            return

        # Static file serving
        rel = path.lstrip("/") or "index.html"
        f = (STATIC_DIR / rel).resolve()
        if STATIC_DIR not in f.parents and f != STATIC_DIR / "index.html":
            self.send_response(403)
            self.end_headers()
            return
        if not f.exists():
            f = STATIC_DIR / "index.html"
        content_type = "text/html"
        if f.suffix == ".js":
            content_type = "application/javascript"
        elif f.suffix == ".css":
            content_type = "text/css"
        body = f.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    ctx = current_context()
    print(f"CloudSec Lab Console")
    print(f"  current kubectl context : {ctx}")
    print(f"  required context        : {REQUIRED_CONTEXT}")
    if ctx != REQUIRED_CONTEXT:
        print(f"  WARNING: context mismatch — /api/state will return 503 until you switch.")
    print(f"  read-only verbs allowed : {sorted(ALLOWED_VERBS)}")
    print(f"  serving on              : http://{BIND_HOST}:{BIND_PORT}  (localhost only)")
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down.")


if __name__ == "__main__":
    main()
