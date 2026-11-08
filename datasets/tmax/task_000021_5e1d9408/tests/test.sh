#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_standalone.py
import ctypes
import os
import platform
import runpy
import sys

# Install an irreversible seccomp filter that prevents the submitted script
# from executing the oracle (or any other external program).
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

machine = platform.machine().lower()
if machine in ("x86_64", "amd64"):
    execve_nr, execveat_nr = 59, 322
elif machine in ("aarch64", "arm64"):
    execve_nr, execveat_nr = 221, 281
else:
    raise RuntimeError(f"Unsupported architecture for verifier sandbox: {machine}")

BPF_LD = 0x00
BPF_W = 0x00
BPF_ABS = 0x20
BPF_JMP = 0x05
BPF_JEQ = 0x10
BPF_K = 0x00
BPF_RET = 0x06
SECCOMP_RET_ALLOW = 0x7FFF0000
SECCOMP_RET_ERRNO = 0x00050000
EPERM = 1

rules = (SockFilter * 6)(
    SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, execve_nr),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, execveat_nr),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW),
)
prog = SockFprog(len(rules), rules)
libc = ctypes.CDLL(None, use_errno=True)
libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
                       ctypes.c_ulong, ctypes.c_ulong]
libc.prctl.restype = ctypes.c_int
PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2

if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
prog_addr = ctypes.cast(ctypes.pointer(prog), ctypes.c_void_p).value
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, prog_addr, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script = sys.argv[1]
sys.argv = sys.argv[1:]
runpy.run_path(script, run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/token_gen.py"
ORACLE_PATH = "/app/auth_oracle"
SECRET_SALT = 3001367245


def expected_token(user_id, timestamp):
    xor_val = (int(timestamp) & 0xffffffff) ^ SECRET_SALT
    preimage = f"{user_id[::-1]}:{xor_val}".encode()
    return hashlib.sha256(preimage).hexdigest()[:32]


def test_token_gen_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Path is not a file: {AGENT_SCRIPT}"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    rng = random.SystemRandom()
    chars = string.ascii_letters + string.digits

    for i in range(1000):
        user_id_len = rng.randint(4, 16)
        user_id = "".join(rng.choice(chars) for _ in range(user_id_len))
        timestamp = str(rng.randint(1600000000, 1800000000))
        expected = expected_token(user_id, timestamp)

        try:
            result = subprocess.run(
                ["python3", "/tmp/run_standalone.py", AGENT_SCRIPT,
                 user_id, timestamp],
                capture_output=True,
                text=True,
                check=True,
                timeout=2,
            )
            actual = result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(
                f"Agent script failed on input '{user_id}' '{timestamp}': {e.stderr}"
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input '{user_id}' '{timestamp}'")

        assert actual == expected, (
            f"Output mismatch on test {i + 1}/1000!\n"
            f"Input user_id: {user_id}\n"
            f"Input timestamp: {timestamp}\n"
            f"Expected: {expected}\n"
            f"Got: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
