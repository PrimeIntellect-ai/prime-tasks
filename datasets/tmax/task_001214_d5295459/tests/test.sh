#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/sandbox_runner.py
import ctypes
import errno
import os
import platform
import runpy
import sys

# Prevent the submitted Python program and all descendants from executing a
# copied or relocated native oracle. The filter is inherited across forks.
if platform.machine() not in ("x86_64", "amd64"):
    raise RuntimeError("unsupported verifier architecture")

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

BPF_LD_W_ABS = 0x20
BPF_JMP_JEQ_K = 0x15
BPF_RET_K = 0x06
SECCOMP_RET_ALLOW = 0x7fff0000
SECCOMP_RET_ERRNO = 0x00050000
PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2

filters = (SockFilter * 6)(
    SockFilter(BPF_LD_W_ABS, 0, 0, 0),       # seccomp_data.nr
    SockFilter(BPF_JMP_JEQ_K, 0, 1, 59),     # execve
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_JMP_JEQ_K, 0, 1, 322),    # execveat
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(filters), filters)
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(program), 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script = sys.argv[1]
sys.argv = sys.argv[1:]
runpy.run_path(script, run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/log_anomaly_detector"
AGENT_SCRIPT = "/home/user/anomaly_detector.py"
SANDBOX_RUNNER = "/tmp/sandbox_runner.py"
NUM_ITERATIONS = 100


def generate_log_file(path, seed):
    random.seed(seed)
    num_lines = random.randint(10, 500)
    timestamp = 1600000000
    methods = ["GET", "POST", "PUT", "DELETE", "HEAD"]
    http_versions = ["HTTP/1.0", "HTTP/1.1", "HTTP/2.0"]
    status_codes = [200, 301, 400, 403, 404, 500]

    with open(path, "w") as f:
        for _ in range(num_lines):
            timestamp += random.randint(1, 100)
            ip = f"{random.randint(1,255)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,255)}"
            method = random.choice(methods)
            url_path = f"/api/v1/resource_{random.randint(1, 100)}"
            version = random.choice(http_versions)
            status = random.choice(status_codes)
            size = random.randint(0, 50000)
            is_malformed = random.random() < 0.02

            if is_malformed:
                if random.choice([True, False]):
                    line = f"[{timestamp}] {ip} {method} {url_path} {version} {status}\n"
                else:
                    line = f"[{timestamp}] {ip} {method} {url_path} {version}\n"
            else:
                line = f"[{timestamp}] {ip} {method} {url_path} {version} {status} {size}\n"
            f.write(line)


def independently_expected(path):
    output = []
    ewma = 0.0
    sse = 0.0
    valid_lines = 0

    with open(path, "r") as f:
        for line in f:
            tokens = line.split()
            if len(tokens) != 7:
                continue
            ts = tokens[0]
            if len(ts) < 2 or not ts.startswith("[") or not ts.endswith("]"):
                continue
            try:
                size = float(tokens[6])
            except ValueError:
                continue

            output.append(
                f"{ts[1:-1]}\t{tokens[1]}\t{tokens[2]}\t{tokens[3]}\t{tokens[5]}\t{tokens[6]}\n"
            )
            if valid_lines == 0:
                ewma = size
            else:
                ewma = 0.3 * size + 0.7 * ewma
                sse += (size - ewma) * (size - ewma)
            valid_lines += 1

    score = math.sqrt(sse / valid_lines) if valid_lines else 0.0
    output.append(f"ANOMALY_SCORE: {score:.4f}\n")
    return "".join(output)


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), "Oracle is not executable"

    with tempfile.TemporaryDirectory() as tmpdir:
        cases = []
        for i in range(NUM_ITERATIONS):
            input_file = os.path.join(tmpdir, f"input_{i}.log")
            generate_log_file(input_file, seed=42 + i)
            expected = independently_expected(input_file)

            try:
                oracle_result = subprocess.run(
                    [ORACLE_PATH, input_file],
                    capture_output=True,
                    text=True,
                    check=True,
                )
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Oracle failed on iteration {i} with error:\n{e.stderr}")

            assert oracle_result.stdout == expected, (
                f"Oracle was altered or independent expectation failed on iteration {i}"
            )
            cases.append((i, input_file, expected))

        # The agent already had the oracle during the reverse-engineering phase.
        # Remove it for evaluation, while seccomp also prevents execution of any
        # copy the submission may have stashed elsewhere.
        os.unlink(ORACLE_PATH)

        for i, input_file, expected in cases:
            agent_result = subprocess.run(
                ["python3", SANDBOX_RUNNER, AGENT_SCRIPT, input_file],
                capture_output=True,
                text=True,
            )
            if agent_result.returncode != 0:
                with open(input_file, "r") as f:
                    input_content = f.read()
                pytest.fail(
                    f"Agent script failed on iteration {i} with error:\n"
                    f"{agent_result.stderr}\n\nInput:\n{input_content}"
                )

            if agent_result.stdout != expected:
                with open(input_file, "r") as f:
                    input_content = f.read()
                pytest.fail(
                    f"Output mismatch on iteration {i}.\n\n"
                    f"--- Input ---\n{input_content}\n"
                    f"--- Expected Output ---\n{expected}\n"
                    f"--- Agent Output ---\n{agent_result.stdout}\n"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
