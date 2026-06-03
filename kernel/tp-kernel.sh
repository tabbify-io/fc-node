#!/bin/sh
# Run ON THE THINKPAD as root (LOCAL, no mesh needed):
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/kernel/tp-kernel.sh -o k.sh && sudo sh k.sh
# Swaps /opt/tabbify/vmlinux to the docker-capable kernel (sha256-verified), turns
# on the FC serial console, redeploys fc-node, and dumps the console + roster.
# The kernel has CONFIG_DEFAULT_INIT=/init so it runs the injected /init directly.
# SUCCESS: console shows the fc-node entrypoint (no "No working init" panic) and
# the fc VM peer appears in the roster — ideally with a `docker` tag.
set -u
UUID=019e7903-0000-7000-8000-000000000f01
TP=fd5a:1f00:0:4::1
KURL=https://tabbify-releases-leo.s3.amazonaws.com/supervisor/kernel/vmlinux-6.1.128-docker
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:fe89bfc84c25955ec255224cc8dda879e30d3e6d8b59c3d46b5a55fd1da708b6"

echo "=== FC_DEBUG (/run drop-in, writable on NixOS) ==="
mkdir -p /run/systemd/system/tabbify-supervisor.service.d
printf '[Service]\nEnvironment=SUPERVISOR_FC_DEBUG=1\n' > /run/systemd/system/tabbify-supervisor.service.d/fcdebug.conf

echo "=== fetch + verify docker-capable kernel ==="
curl -fsSL "$KURL" -o /opt/tabbify/vmlinux.new || { echo "kernel fetch failed"; exit 1; }
EXP=$(curl -fsL "$KURL.sha256" 2>/dev/null | awk '{print $1}')
GOT=$(sha256sum /opt/tabbify/vmlinux.new | awk '{print $1}')
echo "expected=$EXP"; echo "got     =$GOT"
[ -n "$EXP" ] && [ "$EXP" != "$GOT" ] && { echo "CHECKSUM MISMATCH"; rm -f /opt/tabbify/vmlinux.new; exit 1; }
SZ=$(stat -c%s /opt/tabbify/vmlinux.new 2>/dev/null || echo 0)
[ "$SZ" -gt 1000000 ] || { echo "kernel too small ($SZ)"; rm -f /opt/tabbify/vmlinux.new; exit 1; }
[ -f /opt/tabbify/vmlinux.stock.bak ] || cp -a /opt/tabbify/vmlinux /opt/tabbify/vmlinux.stock.bak 2>/dev/null || true
mv /opt/tabbify/vmlinux.new /opt/tabbify/vmlinux
echo "KERNEL SWAPPED -> $GOT"

echo "=== restart supervisor + redeploy ==="
systemctl daemon-reload; systemctl restart tabbify-supervisor; sleep 22
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/purge" >/dev/null 2>&1; echo purged
sleep 2
( curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" -H "Content-Type: application/json" --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}" >/tmp/dep.out 2>&1 ) &
echo "deploying; waiting 100s for boot + in-VM dockerd + join…"; sleep 100

echo "=== deploy: $(cat /tmp/dep.out 2>/dev/null)"
echo "=== runner log (last 10) ==="; tail -10 /opt/tabbify/data/runners/$UUID.log 2>/dev/null
CON=/opt/tabbify/data/fc/$UUID.console.log
echo "=== CONSOLE markers ==="
grep -iE 'No working init|Run /init|fc-node|readiness shim|dockerd|Kernel panic|VFS: Mounted|EXT4-fs .*mounted' "$CON" 2>/dev/null | tail -25
echo "=== console tail (15) ==="; tail -15 "$CON" 2>/dev/null
echo "=== ROSTER (fc VM peer + docker tag?) ==="
curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | python3 -c 'import json,sys
for p in json.load(sys.stdin).get("peers",[]): print(" ",p.get("display_name"),p.get("ula"),p.get("tags"))' 2>/dev/null || curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | tr ',' '\n' | grep -iE 'display_name|tags'
