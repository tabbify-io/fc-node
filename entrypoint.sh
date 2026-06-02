#!/bin/sh
# PID-managed by tini. Brings up dockerd inside the microVM, then hands off to
# the tabbify-supervisor (which self-detects docker -> reachable, joins the mesh,
# and runs the orchestrator — making this VM a Tabbify node).
set -eu

# Readiness shim FIRST — before dockerd. The OUTER generic-firecracker runtime
# HTTP-probes the guest at tap-IP:8080 within ~30s of boot to decide the microVM
# is healthy and keep it alive; our real node control API is the in-VM
# supervisor's mesh-ULA:8730 (unreachable on the tap). dockerd cold-start in a
# fresh microVM can exceed that 30s window, so the shim must answer IMMEDIATELY
# on boot — independent of dockerd — or the outer probe times out and the VM is
# killed before it can come up. Serve a trivial 200 on :8080 right away.
mkdir -p /tmp/health && printf 'ok\n' > /tmp/health/index.html
# busybox httpd daemonizes (forks to background); reparented to tini after exec.
httpd -p 0.0.0.0:8080 -h /tmp/health && echo "[fc-node] readiness shim on :8080 up (pre-dockerd)"

echo "[fc-node] starting dockerd…"
# docker:dind's entrypoint sets up cgroups/iptables and launches dockerd.
dockerd-entrypoint.sh dockerd >/var/log/dockerd.log 2>&1 &

echo "[fc-node] waiting for dockerd socket…"
i=0
until docker info >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 120 ]; then
    echo "[fc-node] FATAL: dockerd did not become ready in 120s" >&2
    echo "---- dockerd.log ----" >&2
    cat /var/log/dockerd.log >&2 || true
    exit 1
  fi
  sleep 1
done
echo "[fc-node] dockerd is up; starting tabbify-supervisor"

# Hand off. The supervisor now advertises the `docker` capability (daemon is
# reachable) plus `firecracker`/`wasm` as detected, joins the mesh with its own
# ULA, and accepts deploys over the mesh.
exec supervisord
