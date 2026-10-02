#!/bin/bash
# Start the diagnostic HTTP server first, then rootless k3s.
# If k3s exits, keep the server up so / still shows the failure.
set -u

mkdir -p /var/log /home/k3s/.rancher /home/k3s/.kube
touch /var/log/k3s-spike.log
if id k3s >/dev/null 2>&1; then
    chown -R k3s:k3s /home/k3s /var/log/k3s-spike.log || true
fi

if [[ -e /dev/fuse ]]; then
    chmod 666 /dev/fuse 2>/dev/null || true
    echo fuse-overlayfs > /var/log/snapshotter
else
    echo native > /var/log/snapshotter
fi
SNAPSHOTTER="$(cat /var/log/snapshotter)"

python3 /opt/spike/status.py >> /var/log/status.log 2>&1 &

if [[ "$(id -u)" -eq 0 ]] && id k3s >/dev/null 2>&1; then
    kubeconfig=/home/k3s/.kube/k3s.yaml
    run_as=(runuser -u k3s -- env HOME=/home/k3s KUBECONFIG="${kubeconfig}")
else
    kubeconfig="${HOME:-/tmp}/.kube/k3s.yaml"
    mkdir -p "$(dirname "${kubeconfig}")"
    run_as=(env HOME="${HOME:-/tmp}" KUBECONFIG="${kubeconfig}")
fi

(
    for _ in $(seq 1 60); do
        if "${run_as[@]}" kubectl get nodes --no-headers 2>/dev/null | grep -qw Ready; then
            "${run_as[@]}" kubectl apply -f /opt/spike/pause-pod.yaml >> /var/log/k3s-spike.log 2>&1 || true
            break
        fi
        sleep 5
    done
) &

set +e
"${run_as[@]}" k3s server --rootless \
    --snapshotter="${SNAPSHOTTER}" \
    --disable=traefik,servicelb,metrics-server \
    --write-kubeconfig "${kubeconfig}" \
    --write-kubeconfig-mode 644 \
    2>&1 | tee -a /var/log/k3s-spike.log
status=${PIPESTATUS[0]}
echo "k3s exited ${status}" | tee -a /var/log/k3s-spike.log
sleep infinity
