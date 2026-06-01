# fc-node — a Tabbify node that runs INSIDE a Firecracker microVM.
#
# Built as a docker image (build.kind = docker) but deployed with
# runtime = "firecracker": the existing generic-FC path converts this OCI image
# to an ext4 rootfs and boots its entrypoint as the microVM's init. Inside the
# VM, dockerd + the tabbify-supervisor come up and the supervisor joins the SAME
# mesh — so the VM is itself a deployable Tabbify node. Apps (e.g. hello-http,
# runtime = docker) are then deployed INTO this node over the mesh; its own
# dockerd builds + runs them and pushes to the mesh registry (which host-netns
# docker on the serving box could not reach — the recursive node fixes that).
#
# Base = docker-in-docker: its entrypoint already sets up cgroups + starts
# dockerd in a constrained environment, which is exactly what we need in a VM.
FROM docker:27.3.1-dind

# x86_64 ThinkPad is the Веха-1 host. The supervisord/tabbify-runner binaries are
# static-musl, so they run on this Alpine base unchanged.
ARG SUP_VERSION=v1.4.5
ARG ARCH=x86_64
ARG RELEASE_BASE=https://tabbify-releases-leo.s3.eu-central-1.amazonaws.com

# tini = a real PID-1 that reaps dockerd's grandchildren (containerd-shim, etc.).
# git + ca-certificates so the in-VM build runner can `git clone` apps deployed
# into this node. iproute2 for the supervisor's tap/route setup. curl is build-only.
RUN apk add --no-cache tini git ca-certificates iproute2 curl \
 && curl -fsSL "$RELEASE_BASE/supervisor/$SUP_VERSION/$ARCH/supervisord"    -o /usr/local/bin/supervisord \
 && curl -fsSL "$RELEASE_BASE/supervisor/$SUP_VERSION/$ARCH/tabbify-runner" -o /usr/local/bin/tabbify-runner \
 && chmod +x /usr/local/bin/supervisord /usr/local/bin/tabbify-runner \
 && apk del curl

COPY entrypoint.sh /usr/local/bin/fc-node-entrypoint
RUN chmod +x /usr/local/bin/fc-node-entrypoint

ENV SUPERVISOR_DATA_DIR=/var/lib/tabbify
VOLUME /var/lib/tabbify

# tini (PID 1) -> entrypoint: bring up dockerd, then hand off to the supervisor.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/fc-node-entrypoint"]
