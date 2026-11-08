#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/telemetry_parser"
TEST_DATA = "/home/user/hidden_test_packets.bin"
ORACLE_BIN = "/app/telemetry_oracle"
AGENT_BIN = os.path.join(PROJECT_DIR, "target/release/telemetry_parser")


def reference_parse(data):
    output = []

    def parse(offset, end):
        while offset + 3 <= end and offset + 3 <= len(data):
            ptype = data[offset]
            length = data[offset + 1] | (data[offset + 2] << 8)
            offset += 3

            if offset + length > end or offset + length > len(data):
                break

            if ptype == 1:
                output.append(f'{{"type":"SensorData","length":{length}}}')
            elif ptype == 2:
                output.append(f'{{"type":"Container","length":{length}}}')
                if length > 0:
                    parse(offset, offset + length)

            offset += length

    parse(0, len(data))
    return output


def copy_runtime_dependencies(executable, root):
    proc = subprocess.run(["ldd", executable], capture_output=True, text=True, check=True)
    paths = set(re.findall(r"(?:=>\s*)?(/[^^\s()]+)", proc.stdout))
    for source in paths:
        if not os.path.isfile(source):
            continue
        destination = os.path.join(root, source.lstrip("/"))
        os.makedirs(os.path.dirname(destination), mode=0o755, exist_ok=True)
        shutil.copy2(source, destination)
        os.chmod(destination, 0o555)


def run_isolated(data, timeout=3):
    # The submitted program gets only its executable, runtime libraries, and input.
    # In particular, the legacy oracle and files from the submitted project are absent.
    root = tempfile.mkdtemp(prefix="telemetry-sandbox-")
    try:
        os.makedirs(os.path.join(root, "bin"), mode=0o755)
        sandbox_bin = os.path.join(root, "bin", "telemetry_parser")
        shutil.copy2(AGENT_BIN, sandbox_bin)
        os.chmod(sandbox_bin, 0o555)
        copy_runtime_dependencies(AGENT_BIN, root)

        input_path = os.path.join(root, "input.bin")
        with open(input_path, "wb") as f:
            f.write(data)
        os.chmod(input_path, 0o444)

        for dirpath, dirnames, _ in os.walk(root):
            os.chmod(dirpath, 0o755)
            for dirname in dirnames:
                os.chmod(os.path.join(dirpath, dirname), 0o755)

        proc = subprocess.run(
            ["chroot", "--userspec=65534:65534", root,
             "/bin/telemetry_parser", "/input.bin"],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        lines = proc.stdout.strip().split("\n")
        if lines == [""]:
            lines = []
        return proc, lines
    finally:
        shutil.rmtree(root, ignore_errors=True)


def packet(ptype, payload):
    return struct.pack("<BH", ptype, len(payload)) + payload


def random_packet(rng, depth=0):
    kind = rng.randrange(4)
    if kind == 0:
        return packet(1, secrets.token_bytes(rng.randrange(0, 40)))
    if kind == 1 and depth < 4:
        children = b"".join(random_packet(rng, depth + 1)
                            for _ in range(rng.randrange(0, 5)))
        return packet(2, children)
    return packet(rng.choice([0, 3, 7, 127, 255]),
                  secrets.token_bytes(rng.randrange(0, 40)))


def generated_cases():
    cases = [
        b"",
        b"\x01",
        packet(1, b""),
        packet(2, b"") + packet(1, b"OK"),
        struct.pack("<BH", 1, 65535) + b"short",
        packet(9, b"ignored") + packet(1, b"visible"),
        packet(2, packet(1, b"nested") + packet(2, b"")),
        packet(2, struct.pack("<BH", 1, 500) + b"bad"),
    ]

    deep = packet(1, b"end")
    for _ in range(80):
        deep = packet(2, deep)
    cases.append(deep)

    rng = secrets.SystemRandom()
    for _ in range(16):
        data = b"".join(random_packet(rng) for _ in range(rng.randrange(2, 12)))
        mode = rng.randrange(3)
        if mode == 0:
            data += struct.pack("<BH", rng.randrange(256), rng.randrange(1000, 65536))
            data += secrets.token_bytes(rng.randrange(0, 20))
        elif mode == 1:
            data += secrets.token_bytes(rng.randrange(1, 3))
        cases.append(data)
    return cases


def test_telemetry_parser_accuracy():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src/main.rs")), "src/main.rs is missing"

    build_proc = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert build_proc.returncode == 0, f"Cargo build failed:\n{build_proc.stderr}"
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN} after build."
    assert os.path.isfile(TEST_DATA), f"Held-out test data is missing: {TEST_DATA}"
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary is missing: {ORACLE_BIN}"

    with open(AGENT_BIN, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_BIN, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submission is byte-identical to the legacy oracle"

    # Preserve the original held-out comparison, but execute the submission in a
    # sandbox where it cannot delegate parsing to /app/telemetry_oracle.
    oracle_proc = subprocess.run(
        [ORACLE_BIN, TEST_DATA], capture_output=True, text=True, timeout=5
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr}"
    oracle_out = oracle_proc.stdout.strip().split("\n")
    if oracle_out == [""]:
        oracle_out = []

    with open(TEST_DATA, "rb") as f:
        hidden_data = f.read()
    try:
        agent_proc, agent_out = run_isolated(hidden_data, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail("Agent binary timed out (likely infinite loop). Accuracy metric: 0.0 < 0.99")

    assert agent_proc.returncode == 0, f"Agent binary exited with {agent_proc.returncode}: {agent_proc.stderr}"
    matches = sum(1 for a, o in zip(agent_out, oracle_out) if a == o)
    expected_len = len(oracle_out)
    if expected_len == 0:
        accuracy = 1.0 if len(agent_out) == 0 else 0.0
    else:
        accuracy = matches / expected_len
    assert accuracy >= 0.99, (
        f"Accuracy metric is {accuracy:.4f}, which is below the threshold of 0.99. "
        f"Agent output matched {matches} out of {expected_len} lines."
    )

    # Fresh, unpredictable inputs prevent hardcoding the readable held-out file.
    # Expected results are independently derived rather than obtained from the oracle.
    for index, data in enumerate(generated_cases()):
        expected = reference_parse(data)
        try:
            proc, actual = run_isolated(data, timeout=3)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on generated case {index}")
        assert proc.returncode == 0, (
            f"Agent crashed on generated case {index} with exit code "
            f"{proc.returncode}: {proc.stderr}"
        )
        assert actual == expected, (
            f"Incorrect output on generated case {index}.\n"
            f"Expected: {expected!r}\nActual: {actual!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
