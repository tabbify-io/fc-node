#!/bin/sh
# Run ON THE THINKPAD (needs root for runner/FC logs):
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-diag.sh | sudo sh
# Dumps why the per-app runner for fc-node crashloops (its own log + FC console).
UUID="019e7903-0000-7000-8000-000000000f01"

echo "=== /dev/kvm ==="
ls -l /dev/kvm 2>&1

echo "=== runners dir ==="
ls -la /opt/tabbify/data/runners/ 2>&1

echo "=== runner log files for this uuid ==="
find /opt/tabbify -name "*${UUID}*" 2>/dev/null | head -20

echo "=== runner log tail (common locations) ==="
for f in /opt/tabbify/data/runners/${UUID}.log /opt/tabbify/data/runners/${UUID}.out /opt/tabbify/${UUID}.log; do
  [ -f "$f" ] && { echo "--- $f ---"; tail -40 "$f"; }
done

echo "=== FC guest console ==="
tail -60 /opt/tabbify/fc/${UUID}.console.log 2>/dev/null || echo "no FC console log (SUPERVISOR_FC_DEBUG off)"

echo "=== full journal (runner/fc/panic, excluding mesh noise) ==="
journalctl --since "7 min ago" --no-pager 2>/dev/null \
  | grep -iE "firecracker|rootfs|ext4|oci|registry|pull|panic|tabbify[_-]runner|fc::|cold_boot|mkfs|oras|/dev/kvm|requested_ula|join|409|conflict|bind|error|fatal" \
  | grep -viE "holepunch|peer_sync|hole-punch|handshake|forwarding" \
  | tail -60

echo "=== live tabbify-runner / firecracker processes ==="
ps aux 2>/dev/null | grep -E "tabbify-runner|firecracker" | grep -v grep || echo "none running now"
