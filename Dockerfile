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
# Base = docker-in-docker. NOTE: dind's entrypoint assumes a privileged docker
# *container* parent already bind-mounted cgroup2/devpts/mqueue/run; a bare
# Firecracker microVM provides none of these, so our entrypoint.sh mounts them
# itself before starting dockerd. Pin the platform: the base is multi-arch and
# would otherwise resolve to the *builder's* arch — the x86_64 ThinkPad host
# rejects a non-amd64 rootfs at conversion (guard_arch_matches_host).
FROM --platform=linux/amd64 docker:27.3.1-dind

# x86_64 ThinkPad is the Веха-1 host. The supervisord/tabbify-runner binaries are
# static-musl, so they run on this Alpine base unchanged.
ARG SUP_VERSION=v1.4.5
ARG ARCH=x86_64
ARG RELEASE_BASE=https://tabbify-releases-leo.s3.eu-central-1.amazonaws.com

# tini = a real PID-1 that reaps dockerd's grandchildren (containerd-shim, etc.).
# git + ca-certificates so the in-VM build runner can `git clone` apps deployed
# into this node. iproute2 for the supervisor's tap/route setup. curl is build-only.
# busybox-extras provides the `httpd` applet used by entrypoint.sh as the
# :8080 readiness shim for the outer generic-firecracker health probe.
RUN apk add --no-cache tini git ca-certificates iproute2 busybox-extras curl \
 && curl -fsSL "$RELEASE_BASE/supervisor/$SUP_VERSION/$ARCH/supervisord"    -o /usr/local/bin/supervisord \
 && curl -fsSL "$RELEASE_BASE/supervisor/$SUP_VERSION/$ARCH/tabbify-runner" -o /usr/local/bin/tabbify-runner \
 && chmod +x /usr/local/bin/supervisord /usr/local/bin/tabbify-runner \
 && apk del curl

# The guest kernel ip= autoconfig gives no resolver to musl userland; the mesh
# join dials the coordinator by raw IP (no DNS needed), but in-VM `oras`/docker
# pulls resolve hostnames. Bake a public resolver so downstream deploys work.
RUN printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf

COPY entrypoint.sh /usr/local/bin/fc-node-entrypoint
RUN chmod +x /usr/local/bin/fc-node-entrypoint
# NOTE: the kernel runs the injected /init via CONFIG_DEFAULT_INIT="/init" (set in
# kernel/docker.fragment) — no /sbin/init symlink needed (a symlink there loops
# with dind's base /init and ELOOPs).
#
# Make /bin/sh a REAL busybox binary, not a symlink. The OCI->ext4 conversion
# mangles relative symlink targets (alpine's /bin/sh -> "bin/busybox" resolves to
# the non-existent /bin/bin/busybox in the ext4), so the kernel cannot exec the
# /init shell script (#!/bin/sh) -> "No working init found". A regular-file copy
# survives the conversion verbatim.
RUN rm -f /bin/sh && cp /bin/busybox /bin/sh && chmod +x /bin/sh

ENV SUPERVISOR_DATA_DIR=/var/lib/tabbify
VOLUME /var/lib/tabbify

# tini (PID 1) -> entrypoint: bring up dockerd, then hand off to the supervisor.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/fc-node-entrypoint"]
