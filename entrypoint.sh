#!/bin/sh
# PID-1 child of tini, exec'd by the supervisor-generated /init (which mounts
# only /proc /sys /dev). A bare Firecracker microVM is NOT a privileged docker
# container, so nothing sets up the cgroup2/devpts/mqueue/run hierarchy dockerd
# needs, nor (if /dev fell back to an empty tmpfs) the core device nodes. We do
# all of that here, then:
#   1. bring up a :8080 readiness shim BEFORE dockerd — the outer generic-FC
#      runtime HTTP-probes the guest tap-IP:8080 within ~30s to keep the VM
#      alive; dockerd cold-start in a fresh microVM can exceed that window.
#   2. start dockerd (best-effort).
#   3. ALWAYS exec the tabbify-supervisor — the node must join the mesh even if
#      dockerd is degraded (the supervisor advertises the `docker` capability
#      only when the daemon is reachable). Coupling the supervisor's existence
#      to dockerd would kill the VM (panic=1) right after the probe went green.
#
# `set -u` only (NOT -e): almost every step below is best-effort and an already
# -mounted fs / missing node must never abort PID 1 and panic the kernel.
set -u

# --- core device nodes (in case /dev is an empty tmpfs, not devtmpfs) ---------
[ -e /dev/null ]    || mknod -m 666 /dev/null    c 1 3   2>/dev/null || true
[ -e /dev/zero ]    || mknod -m 666 /dev/zero    c 1 5   2>/dev/null || true
[ -e /dev/random ]  || mknod -m 666 /dev/random  c 1 8   2>/dev/null || true
[ -e /dev/urandom ] || mknod -m 666 /dev/urandom c 1 9   2>/dev/null || true
[ -e /dev/console ] || mknod -m 600 /dev/console c 5 1   2>/dev/null || true
mkdir -p /dev/net && { [ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null || true; }

# --- readiness shim FIRST (busybox-extras httpd; daemonizes) ------------------
mkdir -p /tmp/health && printf 'ok\n' > /tmp/health/index.html
httpd -p 0.0.0.0:8080 -h /tmp/health 2>/dev/null || echo "[fc-node] WARN :8080 shim failed to bind" >&2
echo "[fc-node] readiness shim on :8080 (pre-dockerd)"

# --- mounts dockerd/dind need that the generated /init does not provide -------
mkdir -p /sys/fs/cgroup && mount -t cgroup2 none   /sys/fs/cgroup 2>/dev/null || true
mkdir -p /run /run/lock  && mount -t tmpfs  tmpfs  /run          2>/dev/null || true
mkdir -p /dev/shm        && mount -t tmpfs  shm    /dev/shm      2>/dev/null || true
mkdir -p /dev/pts        && mount -t devpts devpts /dev/pts      2>/dev/null || true
mkdir -p /dev/mqueue     && mount -t mqueue mqueue /dev/mqueue   2>/dev/null || true

# --- prefer iptables-legacy ----------------------------------------------------
# Our custom guest kernel has the LEGACY netfilter path (IP_NF_*) fully built-in;
# the nft path may be incomplete. Point dind's iptables at the legacy backend so
# dockerd's bridge/NAT rules install reliably. Best-effort + idempotent.
for b in iptables ip6tables; do
  for p in /usr/sbin /sbin; do
    [ -x "$p/$b-legacy" ] && ln -sf "$p/$b-legacy" "$p/$b" 2>/dev/null || true
  done
done

# --- dockerd (best-effort) ----------------------------------------------------
echo "[fc-node] starting dockerd…"
dockerd-entrypoint.sh dockerd >/var/log/dockerd.log 2>&1 &

echo "[fc-node] waiting for dockerd socket (best-effort, max 60s)…"
i=0
until docker info >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "[fc-node] WARN dockerd not ready in 60s; joining mesh WITHOUT docker tag" >&2
    tail -n 40 /var/log/dockerd.log >&2 2>/dev/null || true
    break
  fi
  sleep 1
done
[ "$i" -le 60 ] && echo "[fc-node] dockerd is up"

# --- hand off to the supervisor UNCONDITIONALLY -------------------------------
echo "[fc-node] starting tabbify-supervisor (joins mesh)"
exec supervisord
