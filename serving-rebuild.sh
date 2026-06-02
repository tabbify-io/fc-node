#!/bin/sh
# Run ON THE SERVING BOX (via SSM): rebuilds fc-node from main, converts to an
# OCI layout (skopeo, local — no IPv6), pushes to the mesh registry by tag AND
# prints the immutable digest (oras, mesh-routed via the supervisor's netns —
# skopeo can't speak IPv6 to the registry, oras can). Avoids the host-docker
# no-mesh-route problem (the pipeline build-push fix is still pending).
set -e
TAG="975907f"
REPO="[fd5a:1f00:0:3::1]:5000/tabbify/019e7903-0000-7000-8000-000000000f01"
ORAS="ghcr.io/oras-project/oras:v1.2.0"

SUP=$(docker ps --format '{{.Names}}' | grep -m1 supervisor)
echo "supervisor container: $SUP"

echo "=== build + convert (inside supervisor container: git + docker CLI + skopeo) ==="
docker exec "$SUP" sh -c 'rm -rf /tmp/fcb && git clone --depth 1 https://github.com/tabbify-io/fc-node /tmp/fcb && echo built-from=$(git -C /tmp/fcb rev-parse HEAD) && docker build -t fcnode-latest /tmp/fcb >/tmp/build.log 2>&1 || { tail -20 /tmp/build.log; exit 1; } && rm -rf /tmp/x.tar /tmp/lay && docker save fcnode-latest -o /tmp/x.tar && skopeo copy --insecure-policy docker-archive:/tmp/x.tar oci:/tmp/lay:t'

echo "=== copy layout to host + oras push (mesh-routed via supervisor netns) ==="
rm -rf /tmp/lay-host && docker cp "$SUP:/tmp/lay" /tmp/lay-host
docker run --rm --network "container:$SUP" -v /tmp/lay-host:/lay "$ORAS" cp --from-oci-layout "/lay:t" --to-plain-http "$REPO:$TAG"

echo "=== resolve immutable digest (use this in the deploy ref) ==="
docker run --rm --network "container:$SUP" "$ORAS" manifest fetch --plain-http --descriptor "$REPO:$TAG" 2>&1 | grep -o '"digest":"sha256:[a-f0-9]*"'
echo "=== done ==="
