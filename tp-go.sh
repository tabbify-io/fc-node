#!/bin/sh
# Run ON THE THINKPAD (needs root for runner/FC logs):
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-go.sh | sudo sh
# One-shot: digest deploy -> wait -> dump the per-app runner log + FC console + roster.
UUID="019e7903-0000-7000-8000-000000000f01"
TP="fd5a:1f00:0:4::1"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:540201ffb8cd772df27029b5692a4848936f064784bd6fcb5f067463877b26e3"

echo "=== DEPLOY (digest ref, runtime=firecracker) ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
  -H "Content-Type: application/json" \
  --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}"
echo
echo "=== waiting 60s for FC build+boot ==="
sleep 60
echo "=== RUNNER LOG (last 35 lines = latest attempt) ==="
tail -35 /opt/tabbify/data/runners/$UUID.log 2>/dev/null || echo "no runner log"
echo "=== FC GUEST CONSOLE ==="
tail -45 /opt/tabbify/fc/$UUID.console.log 2>/dev/null || echo "no FC console (SUPERVISOR_FC_DEBUG off)"
echo "=== ROSTER (fc-node a peer yet?) ==="
curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | tr ',' '\n' | grep -iE 'display_name|fc-node|fd5a:1f00:0' | head -20
