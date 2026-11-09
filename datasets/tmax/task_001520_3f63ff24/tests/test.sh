#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import errno
import os
import platform
import pwd
import random
import runpy
import string
import subprocess
import sys
import tempfile

import pytest


def _write_seccomp_runner():
    runner = r'''import ctypes
import errno
import platform
import runpy
import sys

class SockFilter(ctypes.Structure):
    _fields_ = [("code", ctypes.c_ushort),
                ("jt", ctypes.c_ubyte),
                ("jf", ctypes.c_ubyte),
                ("k", ctypes.c_uint32)]

class SockFprog(ctypes.Structure):
    _fields_ = [("len", ctypes.c_ushort),
                ("filter", ctypes.POINTER(SockFilter))]

machine = platform.machine().lower()
if machine in ("x86_64", "amd64"):
    nr_execve, nr_execveat = 59, 322
elif machine in ("aarch64", "arm64"):
    nr_execve, nr_execveat = 221, 281
else:
    raise RuntimeError("Unsupported architecture for execution sandbox: " + machine)

BPF_LD = 0x00
BPF_W = 0x00
BPF_ABS = 0x20
BPF_JMP = 0x05
BPF_JEQ = 0x10
BPF_K = 0x00
BPF_RET = 0x06
SECCOMP_RET_ERRNO = 0x00050000
SECCOMP_RET_ALLOW = 0x7fff0000
PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2

rules = (SockFilter * 6)(
    SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, nr_execve),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, nr_execveat),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(rules), rules)
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(program)) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script = sys.argv[1]
sys.argv = [script]
runpy.run_path(script, run_name="__main__")
'''
    fd, path = tempfile.mkstemp(prefix="solution_runner_", suffix=".py")
    with os.fdopen(fd, "w") as f:
        f.write(runner)
    os.chmod(path, 0o644)
    return path


def test_fuzz_equivalence():
    agent_script = "/home/user/solution.py"
    oracle_bin = "/app/oracle_bin"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is not a regular file."
    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} does not exist."

    # Generate the original 1000 random alphanumeric strings, length 10-50.
    random.seed(42)
    num_tests = 1000
    inputs = []
    for _ in range(num_tests):
        length = random.randint(10, 50)
        s = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
        inputs.append(s)

    input_data = '\n'.join(inputs) + '\n'
    derived_output = ''.join("XYLON-774:" + value[::-1] + "\n" for value in inputs)

    # Keep the original oracle assertion, and independently validate its answers.
    try:
        oracle_proc = subprocess.run(
            [oracle_bin],
            input=input_data,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_output = oracle_proc.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle binary failed unexpectedly:\n{e.stderr}")

    assert oracle_output == derived_output, "Oracle output did not match the independently derived answers."

    # The task deliberately exposes the oracle during investigation. At verification
    # time, run the submitted script unprivileged with the oracle unreadable and with
    # execve/execveat denied, so neither the oracle nor a previously copied binary can
    # be delegated to by solution.py.
    os.chown(oracle_bin, 0, 0)
    os.chmod(oracle_bin, 0o700)
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    runner = _write_seccomp_runner()
    try:
        agent_proc = subprocess.run(
            [sys.executable, runner, agent_script],
            input=input_data,
            text=True,
            capture_output=True,
            preexec_fn=demote,
            cwd="/home/user"
        )
    finally:
        os.unlink(runner)

    assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"
    agent_output = agent_proc.stdout

    if oracle_output != agent_output:
        oracle_lines = oracle_output.splitlines()
        agent_lines = agent_output.splitlines()

        for i, in_str in enumerate(inputs):
            o_line = oracle_lines[i] if i < len(oracle_lines) else "<missing>"
            a_line = agent_lines[i] if i < len(agent_lines) else "<missing>"
            if o_line != a_line:
                pytest.fail(
                    f"Mismatch on input '{in_str}' (line {i+1}).\n"
                    f"Oracle output: '{o_line}'\n"
                    f"Agent output:  '{a_line}'"
                )

        assert len(oracle_lines) == len(agent_lines), f"Output line counts differ: Oracle={len(oracle_lines)}, Agent={len(agent_lines)}"
        assert oracle_output == agent_output, "Outputs differ in whitespace or formatting."

    assert agent_output == derived_output, "Agent output did not match the independently derived answers."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
