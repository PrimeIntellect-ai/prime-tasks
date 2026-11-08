#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove any oracle-backed helper process the agent may have left running.
pkill -KILL -u user 2>/dev/null || true

cat << 'RUNNER_EOF' > /tmp/run_agent_sandboxed.py
import ctypes
import os
import runpy
import sys

# Install a seccomp filter that prevents the submitted script from delegating
# to the oracle (or another copied executable) via execve/execveat.
PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2
SECCOMP_RET_ERRNO = 0x00050000
SECCOMP_RET_ALLOW = 0x7fff0000
EPERM = 1

BPF_LD = 0x00
BPF_W = 0x00
BPF_ABS = 0x20
BPF_JMP = 0x05
BPF_JEQ = 0x10
BPF_K = 0x00
BPF_RET = 0x06

SYS_execve = 59
SYS_execveat = 322

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

filters = (SockFilter * 6)(
    SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, SYS_execve),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, SYS_execveat),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(filters), filters)
libc = ctypes.CDLL(None, use_errno=True)

if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "prctl(PR_SET_NO_NEW_PRIVS) failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(program)) != 0:
    raise OSError(ctypes.get_errno(), "prctl(PR_SET_SECCOMP) failed")

script = sys.argv[1]
sys.argv = sys.argv[1:]
runpy.run_path(script, run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/log_archiver_oracle"
AGENT_SCRIPT = "/home/user/log_archiver.py"
SANDBOX_RUNNER = "/tmp/run_agent_sandboxed.py"
N_ITERATIONS = 100

LEVELS = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

def generate_random_string(min_len, max_len):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(min_len, max_len)))

def generate_shift_jis_text(include_invalid=False):
    text = generate_random_string(10, 50).encode('shift_jis')
    text += b'\x82\xb1\x82\xf1\x82\xc9\x82\xbf\x82\xcd'
    if include_invalid:
        text += b'\xff\xff'
    return text

def generate_log_file(path, include_invalid=False):
    num_records = random.randint(10, 50)
    with open(path, 'wb') as f:
        for _ in range(num_records):
            date = f"2023-10-01 12:00:{random.randint(10, 59)}"
            level = random.choice(LEVELS)
            source = generate_random_string(3, 10)
            header = f"[{date}] {level}: {source}\n".encode('shift_jis')
            body = generate_shift_jis_text(include_invalid) + b"\n---\n"
            f.write(header + body)

def generate_config_file(path):
    with open(path, 'w') as f:
        f.write("[Filter]\n")
        if random.choice([True, False]):
            f.write(f"min_level = {random.choice(LEVELS)}\n")
        if random.choice([True, False]):
            f.write(f"source_match = {generate_random_string(3, 8)}\n")
        if random.choice([True, False]):
            val = "true" if random.choice([True, False]) else "false"
            f.write(f"ignore_encoding_errors = {val}\n")

def run_command(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, timeout=5)
        return res.returncode, res.stdout, res.stderr
    except subprocess.TimeoutExpired:
        return -1, b"", b"Timeout"

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent artifact is not a file: {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"

    random.seed(secrets.randbits(128))

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N_ITERATIONS):
            config_path = os.path.join(tmpdir, f"config_{i}.ini")
            log_path = os.path.join(tmpdir, f"log_{i}.log")

            generate_config_file(config_path)
            include_invalid = random.random() < 0.1
            generate_log_file(log_path, include_invalid)

            oracle_cmd = [ORACLE_PATH, config_path, log_path]
            agent_cmd = ["python3", SANDBOX_RUNNER, AGENT_SCRIPT, config_path, log_path]

            oracle_code, oracle_out, oracle_err = run_command(oracle_cmd)
            agent_code, agent_out, agent_err = run_command(agent_cmd)

            if oracle_code != agent_code or oracle_out != agent_out:
                with open(config_path, 'r') as f:
                    config_content = f.read()

                error_msg = (
                    f"Mismatch on iteration {i}!\n"
                    f"Config:\n{config_content}\n"
                    f"Oracle exit code: {oracle_code}, Agent exit code: {agent_code}\n"
                    f"Oracle stdout length: {len(oracle_out)}, Agent stdout length: {len(agent_out)}\n"
                    f"Oracle stdout preview: {oracle_out[:200]}\n"
                    f"Agent stdout preview: {agent_out[:200]}\n"
                )
                pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
