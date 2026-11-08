#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import zlib
import struct
import tempfile
import pytest

ORACLE_PATH = "/app/dataset_normalizer"
AGENT_PATH = "/home/user/normalizer"


def generate_random_text():
    length = random.randint(10, 500)
    chars = string.ascii_letters + string.digits + " \t"
    text = "".join(random.choice(chars) for _ in range(length))

    num_missing = random.randint(0, 5)
    for _ in range(num_missing):
        pos = random.randint(0, len(text))
        text = text[:pos] + "MISSING" + text[pos:]

    num_rn = random.randint(0, 5)
    for _ in range(num_rn):
        pos = random.randint(0, len(text))
        text = text[:pos] + "\r\n" + text[pos:]

    return text.encode('utf-8')


def generate_archive(path):
    with open(path, 'wb') as f:
        f.write(b"RSRCH")
        num_chunks = random.randint(1, 10)
        f.write(bytes([num_chunks]))

        for _ in range(num_chunks):
            uncompressed_data = generate_random_text()
            compressed_data = zlib.compress(uncompressed_data)

            f.write(struct.pack("<I", len(uncompressed_data)))
            f.write(struct.pack("<I", len(compressed_data)))
            f.write(compressed_data)


def assert_no_delegation(trace_path):
    with open(trace_path, 'r', errors='replace') as f:
        trace = f.read()

    # The initial exec of AGENT_PATH is expected. Any further exec/execveat means
    # the submitted program delegated its work to another executable.
    exec_calls = re.findall(r'\bexecve(?:at)?\s*\(', trace)
    assert len(exec_calls) == 1, \
        f"Agent delegated execution to another program. Exec trace:\n{trace}"


def run_traced_agent(args, trace_path):
    proc = subprocess.run(
        ["strace", "-f", "-e", "trace=execve,execveat", "-o", trace_path,
         AGENT_PATH, *args],
        capture_output=True
    )
    assert_no_delegation(trace_path)
    return proc


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary {AGENT_PATH} not found."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable."

    with open(AGENT_PATH, 'rb') as f:
        agent_data = f.read()
    with open(ORACLE_PATH, 'rb') as f:
        oracle_data = f.read()
    assert agent_data != oracle_data, "Agent binary is byte-identical to the reference implementation."


def test_fuzz_equivalence():
    random.seed(42)

    for i in range(100):
        with tempfile.TemporaryDirectory() as tmpdir:
            input_archive = os.path.join(tmpdir, "input.rsrch")
            generate_archive(input_archive)

            oracle_output = os.path.join(tmpdir, "oracle_out.txt")
            agent_output = os.path.join(tmpdir, "agent_out.txt")
            exec_trace = os.path.join(tmpdir, "agent_exec.trace")

            oracle_proc = subprocess.run(
                [ORACLE_PATH, input_archive, oracle_output], capture_output=True
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on input {i}"

            agent_proc = run_traced_agent(
                [input_archive, agent_output], exec_trace
            )
            assert agent_proc.returncode == 0, \
                f"Agent failed on input {i}. Stderr: {agent_proc.stderr.decode('utf-8', errors='ignore')}"

            assert os.path.exists(oracle_output), f"Oracle did not produce output for input {i}"
            assert os.path.exists(agent_output), f"Agent did not produce output for input {i}"

            with open(oracle_output, 'rb') as f:
                oracle_data = f.read()
            with open(agent_output, 'rb') as f:
                agent_data = f.read()

            assert oracle_data == agent_data, \
                f"Output mismatch on input {i}. Agent output does not match oracle."


def test_atomic_rename_behavior():
    random.seed(99)
    with tempfile.TemporaryDirectory() as tmpdir:
        input_archive = os.path.join(tmpdir, "input.rsrch")
        generate_archive(input_archive)
        agent_output = os.path.join(tmpdir, "agent_out.txt")
        trace_path = os.path.join(tmpdir, "agent_file.trace")

        strace_proc = subprocess.run(
            ["strace", "-f", "-e",
             "trace=execve,execveat,rename,renameat,renameat2",
             "-o", trace_path, AGENT_PATH, input_archive, agent_output],
            capture_output=True, text=True
        )

        assert strace_proc.returncode == 0, "Agent failed during strace."
        assert_no_delegation(trace_path)

        with open(trace_path, 'r', errors='replace') as f:
            trace = f.read()
        expected_tmp = agent_output + ".tmp"

        assert expected_tmp in trace and agent_output in trace, \
            "Could not find atomic rename from .tmp to final output file in strace output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
