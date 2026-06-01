#!/bin/sh
# PID-managed by tini. Brings up dockerd inside the microVM, then hands off to
# the tabbify-supervisor (which self-detects docker -> reachable, joins the mesh,
# and runs the orchestrator — making this VM a Tabbify node).
set -eu

echo "[fc-node] starting dockerd…"
# docker:dind's entrypoint sets up cgroups/iptables and launches dockerd.
dockerd-entrypoint.sh dockerd >/var/log/dockerd.log 2>&1 &

echo "[fc-node] waiting for dockerd socket…"
i=0
until docker info >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "[fc-node] FATAL: dockerd did not become ready in 60s" >&2
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
