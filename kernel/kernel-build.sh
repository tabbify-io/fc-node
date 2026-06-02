#!/bin/sh
# Run ON THE SERVING BOX (x86_64, host docker + S3 instance role) via SSM.
# Builds the docker-capable Firecracker x86_64 vmlinux and uploads it to S3.
# The TP then swaps /opt/tabbify/vmlinux to this and the in-VM dockerd can run
# real containers (bridge + veth + iptables NAT + overlay2).
set -e
S3="s3://tabbify-releases-leo/firecracker"
URL="https://tabbify-releases-leo.s3.amazonaws.com/firecracker/vmlinux-6.1.128-docker"

echo "=== disk before ==="
df -h / /var/lib/docker 2>/dev/null | sort -u

echo "=== clone fc-node kernel/ ==="
rm -rf /tmp/fck && git clone --depth 1 https://github.com/tabbify-io/fc-node /tmp/fck
cd /tmp/fck/kernel

echo "=== build vmlinux (BuildKit, JOBS=$(nproc)) — this is the long part ==="
rm -rf /tmp/fckout
DOCKER_BUILDKIT=1 docker build -f Dockerfile.fckernel \
  --build-arg JOBS="$(nproc)" \
  --target export --output type=local,dest=/tmp/fckout .

echo "=== artifact ==="
file /tmp/fckout/vmlinux
ls -la /tmp/fckout/
SHA=$(cat /tmp/fckout/vmlinux.sha256)
echo "sha256=$SHA"

echo "=== upload to S3 ==="
aws s3 cp /tmp/fckout/vmlinux        "$S3/vmlinux-6.1.128-docker"
aws s3 cp /tmp/fckout/vmlinux.sha256 "$S3/vmlinux-6.1.128-docker.sha256"

echo "=== verify public fetch ==="
curl -fsI "$URL" >/dev/null && echo "PUBLIC OK: $URL" || echo "WARN: $URL not publicly fetchable (may need --acl public-read or bucket policy)"
echo "=== done; kernel url: $URL  sha256: $SHA ==="
