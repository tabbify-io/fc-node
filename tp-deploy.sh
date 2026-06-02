#!/bin/sh
# Run ON THE THINKPAD:  curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-deploy.sh | sh
# Deploys the shimmed fc-node image (already in the mesh registry) to the local
# supervisor as a firecracker microVM, waits, then dumps the launch journal.
set -u
TP="fd5a:1f00:0:4::1"
UUID="019e7903-0000-7000-8000-000000000f01"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01:773c2cdb2cb5df7ce317633483d76aa0b2219492"

echo "=== DEPLOY ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
  -H "Content-Type: application/json" \
  --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}"
echo
echo "=== waiting 50s for FC boot ==="
sleep 50
echo "=== SUPERVISOR LAUNCH JOURNAL ==="
journalctl -u tabbify-supervisor --since "3 min ago" --no-pager 2>/dev/null \
  | grep -iE 'firecracker|fc-|run_fc|rootfs|ext4|oci|registry|pull|ready|runner|launch|spawn|health|docker|cold_boot|wait_until|tap|kvm' \
  | tail -50
echo "=== (guest console — run separately if you want guest internals): ==="
echo "  sudo tail -60 /opt/tabbify/fc/$UUID.console.log"
