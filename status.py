#!/usr/bin/env python3
"""Diagnostics and readiness for the rootless k3s spike."""

import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KUBECTL = [
    "runuser",
    "-u",
    "k3s",
    "--",
    "env",
    "HOME=/home/k3s",
    "KUBECONFIG=/home/k3s/.kube/k3s.yaml",
    "kubectl",
]


def run(cmd, timeout=8):
    try:
        completed = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = (completed.stdout or "") + (completed.stderr or "")
        return f"$ {cmd}\nexit {completed.returncode}\n{output}".rstrip()
    except Exception as exc:
        return f"$ {cmd}\nerror {exc}"


def diagnostics():
    commands = [
        "id",
        "runuser -u k3s -- id",
        "grep -E 'Cap(Bnd|Eff|Prm|Inh|Amb)' /proc/self/status",
        "stat -fc %T /sys/fs/cgroup || true",
        "unshare --user echo userns-ok",
        "test -e /dev/fuse && echo fuse=yes || echo fuse=no",
        "test -e /dev/net/tun && echo tun=yes || echo tun=no",
        "cat /sys/fs/cgroup/cgroup.controllers 2>&1 || true",
        "cat /sys/fs/cgroup/cgroup.subtree_control 2>&1 || true",
        "cat /proc/sys/kernel/unprivileged_userns_clone 2>&1 || true",
        "cat /proc/sys/user/max_user_namespaces 2>&1 || true",
        "cat /etc/subuid /etc/subgid",
        "ls -l \"$(command -v newuidmap)\" \"$(command -v newgidmap)\" 2>&1 || true",
        "cat /var/log/snapshotter 2>/dev/null || true",
        "tail -n 80 /var/log/k3s-spike.log 2>/dev/null || echo 'k3s log is empty'",
    ]
    return "\n\n".join(run(command) for command in commands) + "\n"


def kubectl(args, timeout=15):
    try:
        completed = subprocess.run(
            KUBECTL + args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = (completed.stdout or "") + (completed.stderr or "")
        return completed.returncode, output
    except Exception as exc:
        return 1, str(exc)


def node_is_ready(node_output, exit_code):
    if exit_code != 0:
        return False
    for line in node_output.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "Ready":
            return True
    return False


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/ready":
            exit_code, node_output = kubectl(["get", "nodes", "-o", "wide"])
            _, pod_output = kubectl(["get", "pod", "pause", "-o", "wide"])
            body = node_output.rstrip() + "\n\n" + pod_output.rstrip() + "\n"
            status = 200 if node_is_ready(node_output, exit_code) else 503
            self.respond(status, body)
            return
        if path == "/":
            self.respond(200, diagnostics())
            return
        self.respond(404, "not found\n")

    def respond(self, status, text):
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
