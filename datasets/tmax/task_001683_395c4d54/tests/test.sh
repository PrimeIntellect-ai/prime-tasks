#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pwd
import random
import secrets
import shutil
import stat
import subprocess
import tempfile
import textwrap
import time
import pytest


def kill_stale_user_processes(uid):
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/status", "r") as f:
                lines = f.readlines()
            uid_line = next(line for line in lines if line.startswith("Uid:"))
            real_uid = int(uid_line.split()[1])
            if real_uid == uid:
                os.kill(int(entry), 9)
        except (FileNotFoundError, ProcessLookupError, PermissionError, StopIteration, ValueError):
            pass


def make_runner():
    runner_dir = tempfile.mkdtemp(prefix="solution-runner-", dir="/tmp")
    runner_path = os.path.join(runner_dir, "runner.py")
    source = r'''
import ctypes
import errno
import platform
import runpy
import sys

class SockFilter(ctypes.Structure):
    _fields_ = [
        ("code", ctypes.c_ushort),
        ("jt", ctypes.c_ubyte),
        ("jf", ctypes.c_ubyte),
        ("k", ctypes.c_uint),
    ]

class SockFprog(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_ushort),
        ("filter", ctypes.POINTER(SockFilter)),
    ]

machine = platform.machine().lower()
if machine in ("x86_64", "amd64"):
    exec_syscalls = (59, 322)       # execve, execveat
elif machine in ("aarch64", "arm64"):
    exec_syscalls = (221, 281)
else:
    raise RuntimeError("Unsupported architecture for verifier sandbox: " + machine)

# Once Python has started, deny every attempt by the submitted program or its
# descendants to execute another program. This prevents use of the oracle or
# of a copied oracle while leaving ordinary pure-Python scoring unrestricted.
filters = [SockFilter(0x20, 0, 0, 0)]  # BPF_LD | BPF_W | BPF_ABS, syscall nr
for number in exec_syscalls:
    filters.append(SockFilter(0x15, 0, 1, number))  # JEQ; deny on match
    filters.append(SockFilter(0x06, 0, 0, 0x00050000 | errno.EACCES))
filters.append(SockFilter(0x06, 0, 0, 0x7fff0000))  # SECCOMP_RET_ALLOW
array = (SockFilter * len(filters))(*filters)
program = SockFprog(len(filters), array)
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(38, 1, 0, 0, 0) != 0:  # PR_SET_NO_NEW_PRIVS
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(22, 2, ctypes.byref(program), 0, 0) != 0:  # PR_SET_SECCOMP, FILTER
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script = sys.argv[1]
sys.argv = [script] + sys.argv[2:]
runpy.run_path(script, run_name="__main__")
'''
    with open(runner_path, "w") as f:
        f.write(textwrap.dedent(source))
    os.chmod(runner_dir, 0o755)
    os.chmod(runner_path, 0o444)
    return runner_dir, runner_path


def test_solution_fuzz_equivalence():
    oracle_path = "/app/oracle_bin"
    agent_script = "/home/user/solution.py"

    assert os.path.exists(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle binary at {oracle_path} is not executable"
    assert os.path.exists(agent_script), f"Agent solution not found at {agent_script}"
    assert os.path.isfile(agent_script), f"Agent solution is not a regular file: {agent_script}"
    assert not os.path.islink(agent_script), "Agent solution must not be a symlink"

    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    num_tests = 200
    rng = secrets.SystemRandom()
    test_inputs = [
        "".join(rng.choice(charset) for _ in range(rng.randint(5, 50)))
        for _ in range(num_tests)
    ]

    expected = []
    for test_input in test_inputs:
        try:
            oracle_result = subprocess.run(
                [oracle_path, test_input],
                capture_output=True,
                text=True,
                check=True,
                timeout=2
            )
            expected.append(oracle_result.stdout.strip())
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle binary failed on input '{test_input}'.\nStderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle binary timed out on input '{test_input}'.")

    user = pwd.getpwnam("user")
    kill_stale_user_processes(user.pw_uid)
    time.sleep(0.05)
    runner_dir, runner_path = make_runner()
    original_mode = stat.S_IMODE(os.stat(oracle_path).st_mode)

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        # The oracle remains available for investigation during the task, but
        # is unreadable and unexecutable while submitted code is being tested.
        os.chmod(oracle_path, 0)

        for test_input, oracle_output in zip(test_inputs, expected):
            try:
                agent_result = subprocess.run(
                    ["/usr/bin/python3", "-I", runner_path, agent_script, test_input],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=2,
                    cwd="/home/user",
                    preexec_fn=demote
                )
                agent_output = agent_result.stdout.strip()
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Agent solution failed on input '{test_input}'.\nStderr: {e.stderr}")
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent solution timed out on input '{test_input}'.")

            assert agent_output == oracle_output, (
                f"Mismatch on input: '{test_input}'\n"
                f"Oracle output: '{oracle_output}'\n"
                f"Agent output:  '{agent_output}'"
            )
    finally:
        os.chmod(oracle_path, original_mode)
        shutil.rmtree(runner_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
