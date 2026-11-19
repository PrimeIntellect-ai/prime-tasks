#!/usr/bin/env python3
"""Run Comparator's sandboxed commands under bubblewrap instead of landrun.

Prime Intellect addition. Comparator confines every `lake build` and `lean4export` it starts with
landrun, which relies on the kernel's Landlock LSM. Prime VM guests are built without Landlock, so
landrun's `--best-effort` mode would run those commands unconfined. grade.py points Comparator here
through COMPARATOR_LANDRUN instead. This accepts exactly the landrun arguments Comparator passes and
applies the same policy with bubblewrap namespaces:

  landrun (as Comparator calls it)        bubblewrap
  --ro /                                  --ro-bind / /
  --ro P, --rox P                         nothing more: already readable under /
  --rw /dev                               --dev /dev (a fresh minimal /dev)
  --rwx P                                 --bind P P
  TCP denied (no --unrestricted-network)  --unshare-net
  --env KEY, --env KEY=VALUE              --clearenv, then --setenv KEY VALUE

The command also gets fresh user, PID, IPC and UTS namespaces, so it cannot see, signal or ptrace the
grader's processes outside (Landlock scopes ptrace the same way). landrun's `-ldd`/`-add-exec`
execution allow-list has no bubblewrap equivalent and is not reproduced: everything readable is
executable, inside a read-only file system with no network. Any other argument is an error, so a
change in how Comparator calls landrun cannot silently weaken the sandbox.
"""

from __future__ import annotations

import os
import sys

IGNORED = {"--best-effort", "--ldd", "--add-exec"}
WITH_VALUE = {"--ro", "--rox", "--rw", "--rwx", "--env"}


def bwrap_args(argv: list[str]) -> list[str]:
    readable, writable, env = [], [], {}
    dev = False
    i = 0
    while True:
        if i >= len(argv):
            raise SystemExit("landrun-bwrap: no `--` before the command")
        arg = argv[i]
        if arg == "--":
            command = argv[i + 1 :]
            break
        flag = "--" + arg.lstrip("-")
        if flag in IGNORED:
            i += 1
            continue
        if flag not in WITH_VALUE or i + 1 >= len(argv):
            raise SystemExit(f"landrun-bwrap: unsupported argument {arg!r}")
        value = argv[i + 1]
        if flag == "--env":
            key, sep, val = value.partition("=")
            if sep:
                env[key] = val
            elif key in os.environ:
                env[key] = os.environ[key]
        elif flag in ("--ro", "--rox"):
            readable.append(value)
        elif flag == "--rw" and value == "/dev":
            dev = True
        else:
            writable.append(os.path.realpath(value))
        i += 2
    if not command:
        raise SystemExit("landrun-bwrap: empty command")
    if "/" not in readable:
        raise SystemExit("landrun-bwrap: expected `--ro /`")

    args = [
        "bwrap",
        "--unshare-user", "--unshare-pid", "--unshare-ipc", "--unshare-uts", "--unshare-net",
        "--unshare-cgroup-try", "--die-with-parent", "--new-session", "--cap-drop", "ALL",
        "--clearenv",
    ]  # fmt: skip
    for key, val in env.items():
        args += ["--setenv", key, val]
    args += ["--ro-bind", "/", "/", "--proc", "/proc"]
    if dev:
        args += ["--dev", "/dev"]
    for path in writable:
        args += ["--bind", path, path]
    return [*args, "--chdir", os.getcwd(), "--", *command]


if __name__ == "__main__":
    os.execvp("bwrap", bwrap_args(sys.argv[1:]))
