# Rootless k3s on Aiven Runtime (spike)

This repository answers one question: can `k3s server --rootless` bring a node to Ready inside an Aiven Runtime application container?

It is not an aiven-labs template yet. Catalog submission waits on the result recorded at the bottom of this file.

## What runs

`Containerfile` copies the `k3s` binary from `rancher/k3s:v1.37.1-k3s1` into a Debian image with `uidmap`, `slirp4netns`, and `fuse-overlayfs`. The entrypoint:

1. Serves diagnostics on `0.0.0.0:8080` before k3s starts, and leaves that server up if k3s exits.
2. Runs `k3s server --rootless` as the unprivileged user `k3s`.
3. Uses `fuse-overlayfs` when `/dev/fuse` exists, otherwise the `native` snapshotter.
4. Disables traefik, servicelb, and metrics-server.
5. Applies `pause-pod.yaml` (`registry.k8s.io/pause:3.10`) once a node is Ready.

`GET /` returns host diagnostics and the k3s log tail. `GET /ready` returns 200 only when `kubectl get nodes` shows a node in status `Ready`. The body also includes the pause pod.

## Local preflight

A local run does not use `--privileged`, a host cgroup mount, or the stock `rancher/k3s` entrypoint. On a Mac, Docker executes in a Linux VM, so a local failure does not decide the spike. Aiven does.

```sh
docker build -t k3s-rootless-spike .
docker run --rm -p 8080:8080 k3s-rootless-spike
```

In another shell:

```sh
curl -sS http://127.0.0.1:8080/
curl -sS -D- http://127.0.0.1:8080/ready
```

## Deploying to Aiven Runtime

1. Push this repo to a Git provider connected to the Aiven project.
2. Create one application from `Containerfile` (build context `.`, port 8080).
3. Use an application plan with at least 2 GB RAM (`startup-100-2048` when that plan is listed) so an OOM is not mistaken for a privilege failure.
4. Do not attach data services.
5. Open the public URL `/` and `/ready`, and read the service logs.

## Pass / fail

Pass only when all three are true:

- `/` stays up and shows the diagnostics.
- `/ready` reports a Ready node within about 5 minutes.
- The pause pod reaches `Running`. That is the proof a nested container started.

Fail when `/` or the logs show `operation not permitted` on `unshare` or `clone`, `newuidmap` failing to write `uid_map`, missing cgroup delegation, or the kubelet exiting because cgroup v2 is not delegated. A failure is recorded here and the k3s template is not submitted. The next design is a control plane plus virtual-kubelet workers, with cluster state in Aiven PostgreSQL.

## Result

### Local preflight (2026-10-02)

Host port 8080 was already allocated, so the container was published on `18080:8080`. No `--privileged` flag, no host cgroup mount.

`GET /` stayed up. Relevant diagnostics:

- `unshare --user` failed: `Operation not permitted`.
- cgroup filesystem type is `cgroup2fs`, but `cgroup.subtree_control` is empty.
- `/dev/fuse` and `/dev/net/tun` are absent, so the snapshotter is `native`.
- k3s log: `failed to start the child: fork/exec /proc/self/exe: operation not permitted`, then `k3s exited 1`.
- `GET /ready` returned 503. The pause pod was not created.

This Mac Docker preflight does not decide the spike. Aiven Runtime is the pass/fail.

### Aiven Runtime

Pending deploy.
