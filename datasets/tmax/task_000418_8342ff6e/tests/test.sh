#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_solution_noexec.py
import ctypes
import runpy
import sys

# Install a seccomp filter that prevents the submitted Python program from
# executing external binaries (including copies of the oracle).
class SockFilter(ctypes.Structure):
    _fields_ = [
        ("code", ctypes.c_ushort),
        ("jt", ctypes.c_ubyte),
        ("jf", ctypes.c_ubyte),
        ("k", ctypes.c_uint32),
    ]

class SockFprog(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_ushort),
        ("filter", ctypes.POINTER(SockFilter)),
    ]

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
EPERM = 1

# x86_64 syscall numbers: execve and execveat.
rules = (SockFilter * 6)(
    SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, 59),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, 322),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(rules), rules)
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(program), 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script = sys.argv[1]
sys.argv = [script]
runpy.run_path(script, run_name="__main__")
RUNNER_EOF
chmod 755 /tmp/run_solution_noexec.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import stat
import string
import subprocess
import pytest

ORACLE_PATH = "/app/risk_oracle"
AGENT_SCRIPT = "/home/user/solution.py"
RUNNER_PATH = "/tmp/run_solution_noexec.py"


def generate_random_csv():
    num_rows = random.randint(1, 20)
    lines = ["text_data,base_prior"]
    for _ in range(num_rows):
        num_tokens = random.randint(1, 10)
        tokens = []
        for _ in range(num_tokens):
            token_len = random.randint(1, 150)
            token = ''.join(random.choices(string.ascii_letters + string.digits, k=token_len))
            tokens.append(token)
        text_data = "|".join(tokens)
        base_prior = round(random.uniform(0.01, 0.99), 4)
        lines.append(f"{text_data},{base_prior}")
    return "\n".join(lines) + "\n"


def demote_to_user():
    account = pwd.getpwnam("user")
    os.initgroups(account.pw_name, account.pw_gid)
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert stat.S_ISREG(os.lstat(ORACLE_PATH).st_mode), "Oracle must be a regular file"
    assert os.path.isfile(AGENT_SCRIPT), f"Solution script not found at {AGENT_SCRIPT}"

    # The verifier may execute the oracle as root, but the submitted program is
    # run as the unprivileged user and cannot access the installed oracle.
    os.chown(ORACLE_PATH, 0, 0)
    os.chmod(ORACLE_PATH, 0o700)

    random.seed(42)

    for i in range(50):
        input_csv = generate_random_csv()

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_csv,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {i}"
        oracle_output = oracle_proc.stdout

        agent_proc = subprocess.run(
            ["python3", "-I", RUNNER_PATH, AGENT_SCRIPT],
            input=input_csv,
            text=True,
            capture_output=True,
            preexec_fn=demote_to_user
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed on input {i}. Stderr:\n{agent_proc.stderr}")

        agent_output = agent_proc.stdout

        if oracle_output != agent_output:
            pytest.fail(
                f"Mismatch on random input {i}.\n\n"
                f"Input:\n{input_csv}\n\n"
                f"Oracle Output:\n{oracle_output}\n\n"
                f"Agent Output:\n{agent_output}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
