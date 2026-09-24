# Terminal-Bench 2: repaired QEMU tasks

This directory contains only `qemu-startup` and `qemu-alpine-ssh`, exported from
Harbor `terminal-bench/terminal-bench-2` revision 1 (`1.0.0`), dataset digest
`sha256:c6fc2e2382c1dbae99b2d5ecd2f4f4a60c3c01e0d84642d69b4afd92e99d078b`.

Upstream: [harbor-framework/terminal-bench-2](https://github.com/harbor-framework/terminal-bench-2).
The tasks retain their upstream [Apache 2.0 license](LICENSE).

Task instructions, tests, solutions, resources, and timeouts match upstream.
The two tasks use rebuilt images with Debian 11 package sources pinned to
`snapshot.debian.org` at `20260830T000000Z` and git, curl, and CA certificates
preinstalled. Each task declares its image in `task.toml` and its build recipe
in `environment/Dockerfile`.

The images are published as:

- `prime/primeintellect/tb2-qemu-startup:20251031-eol`
- `prime/primeintellect/tb2-qemu-alpine-ssh:20251031-eol`

To build from this directory:

```bash
uv run prime images push tb2-qemu-startup:20251031-eol --context qemu-startup/environment --public
uv run prime images push tb2-qemu-alpine-ssh:20251031-eol --context qemu-alpine-ssh/environment --public
```

The `terminal-bench-2` environment in `prime-envs` loads the other 87 tasks
directly from the upstream Harbor dataset.
