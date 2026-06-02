#!/bin/sh
# Run ON THE THINKPAD *after* it has OTA'd to supervisord v1.4.7 (needs root):
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-redeploy.sh -o r.sh && sudo sh r.sh
# Purges the stale v1.4.6 runner record (which lacks requested_runtime), then
# redeploys the shimmed fc-node by DIGEST as runtime=firecracker, then dumps the
# runner log + roster. With v1.4.7 the respawn preserves the firecracker runtime
# and the 180s start-healthy gate gives the FC build time to come up.
UUID="019e7903-0000-7000-8000-000000000f01"
TP="fd5a:1f00:0:4::1"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:540201ffb8cd772df27029b5692a4848936f064784bd6fcb5f067463877b26e3"

echo "=== supervisor version (want 1.4.7) ==="
journalctl -u tabbify-supervisor --no-pager 2>/dev/null | grep -iE "promoted|self-update|version=|1\.4\.7" | tail -3 || echo "(check journal manually)"

echo "=== PURGE stale record ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/purge"; echo
sleep 3

echo "=== DEPLOY (digest ref, runtime=firecracker) ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
  -H "Content-Type: application/json" \
  --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}"
echo
echo "=== waiting 90s for FC build+boot ==="
sleep 90
echo "=== RUNNER LOG (last 35) ==="
tail -35 /opt/tabbify/data/runners/$UUID.log 2>/dev/null || echo "no runner log"
echo "=== FC CONSOLE ==="
tail -40 /opt/tabbify/fc/$UUID.console.log 2>/dev/null || echo "no FC console"
echo "=== ROSTER (fc-node joined?) ==="
curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | tr ',' '\n' | grep -iE 'display_name|fd5a:1f00:0' | head -20
