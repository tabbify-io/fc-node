#!/bin/sh
# Run ON THE THINKPAD as root, AFTER the docker-capable kernel is in S3:
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/kernel/tp-kernel.sh -o k.sh && sudo sh k.sh
# Swaps /opt/tabbify/vmlinux to the docker-capable kernel (verified by sha256),
# restarts the supervisor, redeploys fc-node, and dumps the roster. SUCCESS
# SIGNAL: the fc-node VM peer gains a `docker` tag (= in-VM dockerd now runs
# containers — the stock kernel could not). Keeps a backup of the stock kernel.
set -u
UUID="019e7903-0000-7000-8000-000000000f01"
TP="fd5a:1f00:0:4::1"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:8239ac45e6ccf0c07f3781387af2828373839d2c6ec07d5b5f9c2c790550a02c"
KURL="https://tabbify-releases-leo.s3.amazonaws.com/supervisor/kernel/vmlinux-6.1.128-docker"

echo "=== fetch + verify docker-capable kernel ==="
curl -fL "$KURL" -o /opt/tabbify/vmlinux.new || { echo "kernel fetch failed (built+uploaded yet?)"; exit 1; }
EXP=$(curl -fsL "$KURL.sha256" 2>/dev/null | awk '{print $1}')
GOT=$(sha256sum /opt/tabbify/vmlinux.new | awk '{print $1}')
echo "expected=$EXP"
echo "got     =$GOT"
[ -n "$EXP" ] && [ "$EXP" != "$GOT" ] && { echo "CHECKSUM MISMATCH — aborting"; rm -f /opt/tabbify/vmlinux.new; exit 1; }
# ELF sanity — best-effort: skip if `file` is absent (NixOS minimal), and only
# abort if `file` is present AND says it's not an ELF. Also reject tiny files.
SZ=$(stat -c%s /opt/tabbify/vmlinux.new 2>/dev/null || echo 0)
[ "$SZ" -gt 1000000 ] || { echo "kernel suspiciously small ($SZ bytes) — aborting"; rm -f /opt/tabbify/vmlinux.new; exit 1; }
if command -v file >/dev/null 2>&1; then
  file /opt/tabbify/vmlinux.new | grep -q "ELF" || { echo "not an ELF vmlinux — aborting"; rm -f /opt/tabbify/vmlinux.new; exit 1; }
fi

echo "=== swap kernel (backup stock) + restart supervisor ==="
[ -f /opt/tabbify/vmlinux.stock.bak ] || cp -a /opt/tabbify/vmlinux /opt/tabbify/vmlinux.stock.bak 2>/dev/null || true
mv /opt/tabbify/vmlinux.new /opt/tabbify/vmlinux
systemctl restart tabbify-supervisor
echo "waiting 25s to rejoin mesh…"; sleep 25

echo "=== redeploy fc-node (boots with the docker-capable kernel) ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/purge" >/dev/null 2>&1 && echo purged
sleep 3
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
  -H "Content-Type: application/json" \
  --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}"
echo
echo "=== waiting 150s for boot + in-VM dockerd + (re)join ==="
sleep 150

echo "=== runner log tail ==="
tail -20 /opt/tabbify/data/runners/$UUID.log 2>/dev/null
echo "=== ROSTER — look for the fc VM supervisor peer WITH a 'docker' tag ==="
curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null \
  | python3 -c 'import sys,json
for p in json.load(sys.stdin).get("peers",[]):
    print(" ", p.get("display_name"), p.get("ula"), p.get("tags"))' 2>/dev/null \
  || curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | tr ',' '\n' | grep -iE 'display_name|ula|tags'
echo "=== if the fc VM peer shows [...,'docker'] => kernel works, ready to deploy hello-http INTO it ==="
