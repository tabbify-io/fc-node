#!/bin/sh
# Run ON THE THINKPAD as root (captures the FC GUEST CONSOLE):
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-debug-deploy.sh -o d.sh && sudo sh d.sh
# Turns on SUPERVISOR_FC_DEBUG (so the microVM's serial console is captured),
# restarts the supervisor, redeploys fc-node by digest, then dumps the runner
# log AND the guest console — the definitive view of whether eth0 comes up,
# dockerd starts, and the :8080 readiness shim binds inside the VM.
UUID="019e7903-0000-7000-8000-000000000f01"
TP="fd5a:1f00:0:4::1"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:5de2c14bd11067c90a840a7c9824cdcf395c95a3a34f61c79b72e0b4e954bd48"

echo "=== enable SUPERVISOR_FC_DEBUG via systemd drop-in + restart ==="
mkdir -p /etc/systemd/system/tabbify-supervisor.service.d
printf '[Service]\nEnvironment=SUPERVISOR_FC_DEBUG=1\n' > /etc/systemd/system/tabbify-supervisor.service.d/fcdebug.conf
systemctl daemon-reload
systemctl restart tabbify-supervisor
echo "restarted; waiting 25s to rejoin mesh…"; sleep 25

echo "=== purge + deploy (digest, firecracker) ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/purge"; echo
sleep 3
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
  -H "Content-Type: application/json" \
  --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}"
echo
echo "=== waiting 100s for build+boot ==="; sleep 100

echo "=== RUNNER LOG (last 25) ==="
tail -25 /opt/tabbify/data/runners/$UUID.log 2>/dev/null
echo "=== FC GUEST CONSOLE (kernel -> init -> eth0/dockerd/shim) ==="
tail -90 /opt/tabbify/fc/$UUID.console.log 2>/dev/null || echo "STILL no console — check ls /opt/tabbify/fc/"
echo "=== ROSTER ==="
curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | tr ',' '\n' | grep -iE 'display_name|fd5a:1f00:0'
