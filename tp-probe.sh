#!/bin/sh
# Run ON THE THINKPAD as root:
#   curl -sSL https://raw.githubusercontent.com/tabbify-io/fc-node/main/tp-probe.sh -o p.sh && sudo sh p.sh
# Re-deploys fc-node (firecracker) and, WHILE the microVM boots, probes the guest
# directly from the host over the /30 tap link. This disambiguates the
# "guest :8080 never ready" failure WITHOUT needing the FC serial console
# (which NixOS makes hard to enable):
#   ping 172.31.0.2 UP  + curl :8080 no-answer  => guest network OK, shim not bound (httpd/image issue)
#   ping 172.31.0.2 DOWN                          => guest has NO network (kernel ip= / eth0 / tap)
UUID="019e7903-0000-7000-8000-000000000f01"
TP="fd5a:1f00:0:4::1"
REF="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01@sha256:33be4137d00c9fada10068f9a4b9f190ae557ac916cfbf05249a25fae25311d3"

echo "=== purge + (re)deploy in background ==="
curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/purge" >/dev/null 2>&1 && echo purged
( curl -sS -X POST "http://[$TP]:8730/v1/apps/$UUID/deploy" \
    -H "Content-Type: application/json" \
    --data "{\"ref\":\"$REF\",\"runtime\":\"firecracker\"}" >/tmp/dep.out 2>&1 ) &

echo "=== probing host->guest 172.31.0.2 for 150s (catches boot attempts) ==="
booted=0
i=0
while [ "$i" -lt 150 ]; do
  i=$((i + 1))
  TAP=$(ip -o addr show 2>/dev/null | grep -o 'fc-tap[0-9]*' | head -1)
  FC=$(pgrep -x firecracker >/dev/null 2>&1 && echo yes || echo no)
  if ping -c1 -W1 172.31.0.2 >/dev/null 2>&1; then PING=UP; else PING=DOWN; fi
  BODY=$(curl -sS -m2 "http://172.31.0.2:8080/" 2>/dev/null)
  RC=$?
  if [ "$RC" -eq 0 ]; then CURL="200:[$BODY]"; else CURL="no-answer"; fi
  # Only print state-changes / interesting ticks to keep output readable.
  if [ "$FC" = "yes" ] || [ "$PING" = "UP" ] || [ "$CURL" != "no-answer" ]; then
    echo "[$i] tap=${TAP:-none} fc=$FC ping172.31.0.2=$PING curl8080=$CURL"
  fi
  if [ "$PING" = "UP" ] && [ "$CURL" != "no-answer" ]; then
    echo ">>> GUEST :8080 ANSWERS — readiness should pass; recursion imminent"
    booted=1
  fi
  sleep 1
done

echo "=== deploy result ==="; cat /tmp/dep.out 2>/dev/null; echo
echo "=== tap detail (host side of /30) ==="; ip addr show 2>/dev/null | grep -A3 fc-tap || echo "(no fc-tap right now)"
echo "=== firecracker procs ==="; pgrep -a firecracker || echo none
echo "=== verdict hint ==="
if [ "$booted" -eq 1 ]; then echo "guest answered :8080 at least once"; else echo "guest NEVER answered; check ping column: all-DOWN=>no guest network, UP-but-no-answer=>shim/httpd not bound"; fi