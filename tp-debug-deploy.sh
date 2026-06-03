#!/bin/sh
# Run ON THE THINKPAD as root (captures the FC GUEST CONSOLE):
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-debug-deploy.sh -o d.sh && sudo sh d.sh
# Turns on SUPERVISOR_FC_DEBUG (so the microVM's serial console is captured),
# restarts the supervisor, redeploys fc-node by digest, then dumps the runner
# log AND the guest console — the definitive view of whether eth0 comes up,
# dockerd starts, and the :8080 readiness shim binds inside the VM.
UUID="019e7903-0000-7000-8000-000000000f01"
TP="fd5a:1f00:0:4::1"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:8239ac45e6ccf0c07f3781387af2828373839d2c6ec07d5b5f9c2c790550a02c"

echo "=== enable SUPERVISOR_FC_DEBUG via systemd drop-in (/run = writable on NixOS) + restart ==="
mkdir -p /run/systemd/system/tabbify-supervisor.service.d
printf '[Service]\nEnvironment=SUPERVISOR_FC_DEBUG=1\n' > /run/systemd/system/tabbify-supervisor.service.d/fcdebug.conf
systemctl daemon-reload
systemctl restart tabbify-supervisor
echo "restarted; waiting 25s to rejoin mesh…"; sleep 25

echo "=== purge + deploy (digest, firecracker) ==="
echo "deploying ref: $REF"
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/purge"; echo
sleep 3
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
  -H "Content-Type: application/json" \
  --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}"
echo
echo "=== waiting 40s for build+boot ==="; sleep 40

echo "=== RUNNER LOG (last 15) ==="
tail -15 /opt/tabbify/data/runners/$UUID.log 2>/dev/null
CONSOLE=/opt/tabbify/data/fc/$UUID.console.log
echo "=== CONSOLE KEY MARKERS (kernel boot / network / shim / panic) ==="
grep -iE 'IP-Config|eth0|Kernel panic|Run /init|fc-node|dockerd|cgroup|Booting|Linux version|Call Trace|VFS:|not syncing' "$CONSOLE" 2>/dev/null | tail -40 || echo "no markers"
echo "=== FC GUEST CONSOLE (last 80 lines) ==="
tail -80 "$CONSOLE" 2>/dev/null || { echo "STILL no console — ls below"; ls -la /opt/tabbify/data/fc/ 2>/dev/null; }
echo "=== ROSTER ==="
curl -s http://3.124.69.92:8888/v1/mesh/peers 2>/dev/null | tr ',' '\n' | grep -iE 'display_name|fd5a:1f00:0'
