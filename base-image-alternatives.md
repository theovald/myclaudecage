# Base Image Alternatives

Current base: `ubuntu:25.10`

## Key constraint: Podman-in-Podman

Rootless Podman needs `uidmap`, `fuse-overlayfs`, `passt` (rootless networking), and `/etc/subuid`/`subgid` support. These are well-packaged on Debian/Ubuntu but painful on Alpine:
- Alpine's `shadow-uidmap` has historically had musl-related quirks
- `passt` isn't in Alpine's repos — requires building from source
- Podman on Alpine with fuse-overlayfs and nested user namespaces is a known source of edge-case bugs

## Alpine issues

- **Node.js / Claude Code**: The `claude.ai/install.sh` script likely assumes glibc. Alpine uses musl, which would break prebuilt Node.js binaries. Claude's install script might not work without patching.
- **SDKMAN + Java**: SDKMAN distributes glibc-linked JDK binaries. On Alpine you'd need `gcompat` or switch to a musl-native JDK (e.g. Alpine-specific Temurin builds).
- **gh CLI**: No `.deb` packages — you'd download the tarball directly. Minor inconvenience, not a blocker.

## Debian slim: the realistic alternative

`debian:bookworm-slim` would be a safe swap:
- ~30MB smaller base (~75MB vs ~105MB)
- All the same packages available (same repos, same glibc)
- Podman, uidmap, passt, fuse-overlayfs all packaged
- NodeSource, gh, SDKMAN all work identically
- Only downside: slightly older package versions than Ubuntu 25.10

## Conclusion

Debian slim saves some image size with zero functional changes. Alpine would save more space but would require reworking Podman-in-Podman, the Claude install, and SDKMAN/Java — not worth it given this image is a dev environment, not a minimal runtime. The bulk of the image size is Java + Node + Podman anyway, not the base layer.
