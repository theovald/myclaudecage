# myclaudecage

Run Claude Code in a sandboxed Podman environment optimized for **Python (uv) and JavaScript (Node.js)** development on **macOS**.

Claude Code reads your code to understand your project and generate pull requests — but it can also read your documents, secrets, and keys if they're on disk. This sandbox isolates Claude to your designated working directory while still letting it edit code, run tests, and interact with GitHub.

### Why Ubuntu?

We use `ubuntu:25.10` as the base image. While larger than Alpine, Ubuntu provides maximum compatibility with development toolchains, Python build dependencies, Node.js binaries, and `glibc`-linked tools like the Claude Code CLI.

## Prerequisites

- **macOS** only
- **Podman**: `brew install podman`
- **GitHub CLI**: `brew install gh` then `gh auth login`

## Quick Start

```bash
gh repo clone theovald/myclaudecage
cd <your-work-folder>
~/myclaudecage/claude-container.sh
```

The image is built automatically on the first run. Because you're inside a container, Claude can't open your browser for OAuth — copy the `claude.ai/oauth/authorize` link from the terminal and open it manually. If the URL wraps across lines, use `./open_url.sh 'URL_HERE'`.

## Options

| Parameter | Description |
| --------- | ----------- |
| `--rebuild` | Force rebuild the container image. Required after modifying `Containerfile.claude`. |
| `--no-token` | Skip GitHub CLI requirement. Claude won't receive a `GH_TOKEN`. |
| `--shell` | Drop into a bash shell instead of starting Claude. |
| `--folder=/path` | Mount an alternative working directory instead of `$PWD`. |
| `-p "prompt"` | Pass arguments through to the Claude CLI. |

Example:
```bash
./claude-container.sh -p "run the fastapi server"
```

## What's mounted

- Your working directory — the only code Claude can see
- `~/.claude` — persistent session history
- `~/.claude.json` — Claude config (with backup)
- `~/.gitconfig` — read-only, copied in at startup
- `claude-uv-cache` volume — isolated Python package cache
- Ports `3000`, `4200`, `5005`, `8000`, `8080` — mapped if free on the host

## The Socket Proxy & Testcontainers

The container supports Testcontainers (e.g. PostgreSQL in tests) by communicating with the macOS Podman socket through a custom **Go-based socket proxy**.

The proxy blocks by default and only forwards a strict allowlist of API endpoints. On create endpoints it parses the JSON body and rejects dangerous configurations:

| Blocked | Detail |
|---|---|
| Privileged containers | `Privileged: true` |
| Host filesystem access | Bind mounts, absolute/relative paths, traversals — only named volumes |
| Namespace escapes | `PidMode`, `IpcMode`, `UTSMode`, `NetworkMode`, `UsernsMode` = `"host"` |
| Dangerous capabilities | `SYS_ADMIN`, `SYS_PTRACE`, `NET_RAW`, `ALL`, etc. |
| Security opt-outs | `seccomp=unconfined`, `apparmor=disabled` |
| Host devices | `/dev/*` device mappings |
| Kernel tuning | Sysctls, tmpfs mounts |
| Dangerous network drivers | `host`, `macvlan`, `ipvlan` |
| Image build / commit | `/build`, `/commit` not in allowlist |
| Operating on the sandbox itself | Lifecycle/I/O restricted to containers the proxy created |

## Security Notes

**SSH keys** are not mounted. GitHub access uses `GH_TOKEN` from the CLI, and Git is configured to translate `git@github.com:` to `https://github.com/` globally.

**GitHub token scope**: Run with `--no-token` if you don't want Claude to push branches or create PRs.

## Cleanup

```bash
./stopAllContainers.sh    # Stop all running containers
./cleanAllContainers.sh   # Full cleanup: containers, images, volumes, networks
```
