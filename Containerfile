ARG K3S_VERSION=v1.37.1-k3s1
FROM rancher/k3s:${K3S_VERSION} AS k3s

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        fuse-overlayfs \
        iptables \
        python3 \
        slirp4netns \
        uidmap \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

# The image k3s binary is a multicall. kubectl, containerd, and crictl must be
# argv0 symlinks. runc, the shim, and aux/ are siblings the kubelet execs.
COPY --from=k3s /bin/k3s /bin/runc /bin/containerd-shim-runc-v2 /usr/local/bin/
COPY --from=k3s /bin/aux /usr/local/bin/aux

RUN useradd --create-home --uid 1000 --shell /bin/bash k3s \
    && grep -q '^k3s:' /etc/subuid || echo 'k3s:100000:65536' >> /etc/subuid \
    && grep -q '^k3s:' /etc/subgid || echo 'k3s:100000:65536' >> /etc/subgid \
    && mkdir -p /opt/spike /var/log \
    && chown k3s:k3s /var/log \
    && ln -sf k3s /usr/local/bin/kubectl \
    && ln -sf k3s /usr/local/bin/containerd \
    && ln -sf k3s /usr/local/bin/crictl

COPY entrypoint.sh status.py pause-pod.yaml /opt/spike/
RUN chmod 755 /opt/spike/entrypoint.sh /usr/local/bin/k3s /usr/local/bin/runc /usr/local/bin/containerd-shim-runc-v2

EXPOSE 8080
ENTRYPOINT ["/opt/spike/entrypoint.sh"]
