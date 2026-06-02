#!/bin/sh
# Run ON THE THINKPAD *after* it has OTA'd to supervisord v1.4.8 (needs root):
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-redeploy.sh -o r.sh && sudo sh r.sh
# Purges the stale runner record, then redeploys the fc-node image (new B1/B2
# entrypoint) by DIGEST as runtime=firecracker, then dumps the runner log +
# roster. v1.4.8 adds guest-egress NAT (so the in-VM supervisor can join the
# mesh) + content-derived ext4 sizing (fixes intermittent mkfs.ext4 failures).
UUID="019e7903-0000-7000-8000-000000000f01"
TP="fd5a:1f00:0:4::1"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:33be4137d00c9fada10068f9a4b9f190ae557ac916cfbf05249a25fae25311d3"

echo "=== supervisor version (want 1.4.8) ==="
journalctl -u tabbify-supervisor --no-pager 2>/dev/null | grep -iE "self-update|version=|1\.4\.8" | tail -3 || echo "(check journal manually)"

echo "=== PURGE stale record ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/purge"; echo
sleep 3

echo "=== DEPLOY (digest ref, runtime=firecracker) ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
  -H "Content-Type: application/json" \
  --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}"
echo
echo "=== waiting 120s for FC build+boot+join ==="
sleep 120
echo "=== RUNNER LOG (last 35) ==="
tail -35 /opt/tabbify/data/runners/$UUID.log 2>/dev/null || echo "no runner log"
echo "=== FC CONSOLE ==="
tail -40 /opt/tabbify/data/fc/$UUID.console.log 2>/dev/null || echo "no FC console (enable via tp-debug-deploy.sh)"
echo "=== ROSTER (fc-node joined?) ==="
curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | tr ',' '\n' | grep -iE 'display_name|fd5a:1f00:0' | head -20
