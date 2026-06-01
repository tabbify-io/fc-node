# fc-node — recursive Tabbify node in a Firecracker microVM

Tabbify hosts itself. `fc-node` is an ordinary deployable project (like any app),
but deploying it produces a **Tabbify node running inside a Firecracker microVM**:

```
ThinkPad (outer supervisor, firecracker+docker tags)
└─ deploy fc-node (runtime=firecracker)  ── generic-FC: OCI image → ext4 → boot
   └─ microVM init = tini → dockerd + supervisord
        supervisor self-detects docker → joins the SAME mesh → own ULA
        → appears in the coordinator roster as a deployable node
        → deploy hello-http (runtime=docker) INTO it over the mesh
           → the VM's own dockerd builds + runs it, pushing to the mesh registry
```

No new runtime, no NixOS, no microvm.nix: it is just **two github projects
(`fc-node` + `hello-http`) + the deploy API choosing target+runtime.** The
recursion is not code — it is "deploy a node project, then deploy into it."

## Why this exists

The serving box's host-netns docker could not push to the mesh-only registry.
A node *inside* a microVM has its own netns on the mesh, so its dockerd reaches
the registry directly. fc-node is that node.

## Deploy

```bash
# 1. Boot the node VM on the ThinkPad:
POST https://api.tabbify.io/v1/deploy
  { "repo_url": "https://github.com/tabbify-io/fc-node", "ref": "<sha>",
    "tenant": "tabbify", "app_uuid": "019e7903-0000-7000-8000-000000000f01",
    "targets": [{ "supervisor": "thinkpad", "runtime": "firecracker" }] }

# 2. Find the VM-node's ULA in the roster:
curl -s http://3.124.69.92:8888/v1/mesh/peers | python3 -m json.tool | grep -A4 fc-node

# 3. Deploy hello-http INTO the VM-node (target = its ULA/name):
POST https://api.tabbify.io/v1/deploy
  { "repo_url": "https://github.com/tabbify-io/hello-http", "ref": "<sha>",
    "tenant": "tabbify", "app_uuid": "019e7903-0000-7000-8000-000000000d03",
    "targets": [{ "supervisor": "<fc-node-ULA-or-name>", "runtime": "docker" }] }

# 4. curl hello-http by its in-VM app-ULA → 200.
```

## The one open question: the kernel

dockerd inside the microVM needs kernel features: `overlayfs`, `bridge` + `veth`,
`netfilter`/`iptables`, `cgroup v2`, and `/dev/net/tun` (for the mesh joiner).
The stock firecracker-ci kernel (`/opt/tabbify/vmlinux`) is minimal and may lack
`bridge`/`netfilter`. The first deploy reveals this:

- **dockerd comes up + node joins mesh** → done; the existing kernel suffices.
- **dockerd fails** → check the serial console (`SUPERVISOR_FC_DEBUG=1`,
  `/opt/tabbify/fc/<uuid>.console.log`). Almost certainly the kernel. Fix = supply
  a docker-capable kernel at `/opt/tabbify/vmlinux` (build/fetch one); nothing else
  changes.

## Build notes

- Base `docker:27.3.1-dind` already runs dockerd in a constrained env.
- `supervisord` + `tabbify-runner` are pulled (static-musl, x86_64) from the
  release bucket at build time — pin `SUP_VERSION` to bump.
- `tini` is PID 1 so dockerd's grandchildren are reaped.
