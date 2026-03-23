# Container Socket Proxy

A filtering reverse proxy for Docker/Podman Unix sockets. Sits between a sandbox container and the host's container runtime, allowing Testcontainers to work while blocking escape vectors.

Every request is **blocked by default** (HTTP 403). Only explicitly allowlisted endpoints and HTTP methods are forwarded. On endpoints that accept a request body, the proxy parses the JSON and rejects dangerous configurations before the request reaches the host runtime. The proxy also tracks which containers were created through it — lifecycle and I/O operations are restricted to these child containers.

## What the proxy blocks

Even on allowed endpoints, the proxy rejects requests that attempt:

| Vector | Block |
|---|---|
| Privileged containers | `Privileged: true` in create body |
| Host filesystem access | Bind mounts, absolute paths, relative paths, path traversal; only named volumes allowed |
| Namespace escapes | `PidMode`, `IpcMode`, `UTSMode`, `NetworkMode`, `UsernsMode` set to `"host"` |
| Dangerous capabilities | Allowlists safe caps only; blocks `SYS_ADMIN`, `SYS_PTRACE`, `NET_RAW`, `ALL` |
| Security opt-outs | `seccomp=unconfined`, `apparmor=disabled` |
| Host devices | `/dev/*` device mappings |
| Kernel tuning | Sysctls, tmpfs mounts |
| Dangerous network drivers | `host`, `macvlan`, `ipvlan`; only `bridge` and isolated drivers allowed |
| Image build / commit | `/build` and `/commit` not in allowlist |
| Swarm / plugins / secrets | Not in allowlist |
| Operating on other containers | Lifecycle/I/O operations restricted to child containers created through the proxy |

## What the proxy allows

Testcontainers and similar frameworks need a working container API. The proxy permits:

- **Container lifecycle** (create, start, stop, kill, remove) — with body filtering on create, restricted to child containers
- **Container I/O** (exec, logs, attach, archive) — child containers only
- **Images** (pull, list, inspect, tag, remove, prune)
- **Networks** (create, list, inspect, connect, disconnect, remove, prune) — safe drivers only
- **Volumes** (create, list, inspect, remove, prune) — named volumes only
- **System** (ping, version, info, events, disk usage)

## Usage

```bash
# Build locally (requires Go 1.22+)
go build -o socket-proxy .

# Or build via container (no Go required)
./build.sh

# Run (auto-detects Podman or Docker socket)
./socket-proxy

# Or specify sockets explicitly
UPSTREAM_SOCKET=/run/user/1000/podman/podman.sock \
LISTEN_SOCKET=/tmp/filtered-podman.sock \
./socket-proxy
```

### Integration with claude-container.sh

The proxy is started automatically by `claude-container.sh` via `start.sh`. The flow:

1. `start.sh` detects the host socket (Podman or Docker)
2. Builds the proxy binary if needed (using a Go container)
3. Starts the proxy in the background on a unique socket (`/tmp/claude-filtered-$$.sock`)
4. The filtered socket is mounted into the container and exposed as `DOCKER_HOST`
5. The proxy is cleaned up when the sandbox exits

## Testing

```bash
# Unit tests (requires Go)
go test -v ./...

# Integration tests against a live proxy
./test-blocked.sh    # verifies attack vectors are blocked
./test-vulns.sh      # vulnerability regression tests
```
