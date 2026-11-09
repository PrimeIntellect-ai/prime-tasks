#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_graph_query.py
import ctypes
import errno
import runpy
import sys

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

# Prevent the submitted Python program from delegating its work to any external
# executable, including a copied or renamed query_oracle.
BPF_LD_W_ABS = 0x20
BPF_JMP_JEQ_K = 0x15
BPF_RET_K = 0x06
SECCOMP_RET_ERRNO = 0x00050000
SECCOMP_RET_ALLOW = 0x7fff0000

filters = (SockFilter * 6)(
    SockFilter(BPF_LD_W_ABS, 0, 0, 0),       # seccomp_data.nr
    SockFilter(BPF_JMP_JEQ_K, 0, 1, 59),    # execve
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_JMP_JEQ_K, 0, 1, 322),   # execveat on x86_64
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(filters), filters)

libc = ctypes.CDLL(None, use_errno=True)
libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
                       ctypes.c_ulong, ctypes.c_ulong]
libc.prctl.restype = ctypes.c_int

PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2

if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER,
              ctypes.addressof(program), 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

agent_path = sys.argv[1]
sys.argv = [agent_path]
runpy.run_path(agent_path, run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest


def generate_fuzz_input():
    num_nodes = random.randint(50, 500)
    num_edges = random.randint(100, 2000)
    num_relations = random.randint(5, 10)

    nodes = [f"N{i}" for i in range(num_nodes)]
    relations = [f"rel{i}" for i in range(num_relations)]

    lines = ["GRAPH"]
    for _ in range(num_edges):
        u = random.choice(nodes)
        v = random.choice(nodes)
        rel = random.choice(relations)
        lines.append(f"{u} {rel} {v}")
    lines.append("END")

    num_queries = 10
    for _ in range(num_queries):
        chain_len = random.randint(1, 4)
        chain = [random.choice(relations) for _ in range(chain_len)]
        lines.append("CHAIN " + " ".join(chain))

    return "\n".join(lines) + "\n"


def test_fuzz_equivalence():
    oracle_path = "/app/query_oracle"
    agent_path = "/home/user/graph_query.py"
    runner_path = "/tmp/run_graph_query.py"

    assert os.path.exists(agent_path), f"Agent script {agent_path} not found."
    assert os.path.isfile(agent_path), f"Agent path {agent_path} is not a file."
    assert os.path.exists(oracle_path), f"Oracle binary {oracle_path} not found."
    assert os.path.isfile(oracle_path), f"Oracle path {oracle_path} is not a file."

    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submission is byte-identical to the reference binary."

    random.seed(42)
    cases = []

    # Obtain all expected answers before making the reference unavailable.
    for i in range(100):
        fuzz_input = generate_fuzz_input()
        oracle_proc = subprocess.run(
            [oracle_path],
            input=fuzz_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"
        cases.append((fuzz_input, oracle_proc.stdout))

    # The submitted program must implement the logic rather than invoke the
    # reference by its documented path. The seccomp runner also blocks execve
    # delegation to any copied or renamed executable.
    os.unlink(oracle_path)
    assert not os.path.exists(oracle_path)

    for i, (fuzz_input, expected_stdout) in enumerate(cases):
        agent_proc = subprocess.run(
            ["python3", runner_path, agent_path],
            input=fuzz_input,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent script failed with non-zero exit code on iteration {i}.\n"
                f"Stderr: {agent_proc.stderr}"
            )

        if expected_stdout != agent_proc.stdout:
            pytest.fail(
                f"Mismatch on iteration {i}.\n\n"
                f"--- Input ---\n{fuzz_input}\n"
                f"--- Expected (Oracle) Output ---\n{expected_stdout}\n"
                f"--- Actual (Agent) Output ---\n{agent_proc.stdout}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
