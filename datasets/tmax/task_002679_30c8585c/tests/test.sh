#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import string
import subprocess

import pytest


def python_oracle(input_bytes: bytes) -> bytes:
    """Implement the payload_encoder transformation independently."""
    key = b"G0PH3R"
    xored = bytearray()
    for i, b in enumerate(input_bytes):
        xored.append(b ^ key[i % len(key)])
    return base64.b64encode(xored)[::-1]


def test_evidence_extracted():
    """Test that the evidence archive was extracted to the correct location."""
    evidence_dir = "/home/user/evidence"
    assert os.path.isdir(evidence_dir), f"Evidence directory missing: {evidence_dir}"

    payload_encoder = os.path.join(evidence_dir, "payload_encoder")
    assert os.path.isfile(payload_encoder), f"payload_encoder binary missing from {evidence_dir}"


def test_agent_source_exists():
    """Require the requested nonempty Go source file."""
    source = "/home/user/encoder.go"
    assert os.path.isfile(source), f"Go source missing: {source}"
    assert os.path.getsize(source) > 0, f"Go source is empty: {source}"


def test_agent_binary_exists():
    """Test that the agent's binary exists, is executable, and is a Go executable."""
    agent_bin = "/home/user/encoder"
    assert os.path.isfile(agent_bin), f"Agent binary missing: {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable: {agent_bin}"

    result = subprocess.run(
        ["go", "version", "-m", agent_bin],
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Agent binary does not contain valid Go build information: "
        f"{result.stderr.decode(errors='replace')}"
    )

    reference = "/home/user/evidence/payload_encoder"
    if os.path.isfile(reference):
        with open(agent_bin, "rb") as submitted, open(reference, "rb") as original:
            assert submitted.read() != original.read(), (
                "Agent binary is byte-identical to the untrusted payload_encoder"
            )


@pytest.fixture(scope="session")
def rebuilt_binary(tmp_path_factory):
    """Compile the submitted source independently for behavioral testing."""
    source = "/home/user/encoder.go"
    assert os.path.isfile(source), f"Go source missing: {source}"
    output = tmp_path_factory.mktemp("go-build") / "encoder"
    result = subprocess.run(
        ["go", "build", "-o", str(output), source],
        capture_output=True,
        timeout=30,
        cwd="/home/user",
    )
    assert result.returncode == 0, (
        "Submitted encoder.go does not compile successfully.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert output.is_file() and os.access(output, os.X_OK)
    return str(output)


def run_and_check(binary, input_bytes, description):
    try:
        result = subprocess.run(
            [binary],
            input=input_bytes,
            capture_output=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{description} timed out on input length {len(input_bytes)}")
    except Exception as exc:
        pytest.fail(f"{description} execution failed: {exc}")

    assert result.returncode == 0, (
        f"{description} exited with non-zero code {result.returncode} on input "
        f"length {len(input_bytes)}. Stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def test_fuzz_equivalence():
    """
    Fuzz equivalence test:
    Generate 500 random printable ASCII strings of length 1-1000.
    Run the agent's binary and compare output to the oracle.
    """
    agent_bin = "/home/user/encoder"
    assert os.path.isfile(agent_bin), f"Agent binary missing: {agent_bin}"

    random.seed(1337)
    printable_chars = string.printable

    for i in range(500):
        length = random.randint(1, 1000)
        input_str = "".join(random.choice(printable_chars) for _ in range(length))
        input_bytes = input_str.encode("utf-8")
        expected_output = python_oracle(input_bytes)
        actual_output = run_and_check(agent_bin, input_bytes, "Agent binary")

        if actual_output != expected_output:
            pytest.fail(
                f"Mismatch on input #{i+1} (length {length}).\n"
                f"Input (repr): {repr(input_str[:50])}...\n"
                f"Expected (repr): {repr(expected_output[:50])}...\n"
                f"Actual (repr): {repr(actual_output[:50])}..."
            )


def test_rebuilt_source_equivalence(rebuilt_binary):
    """Exercise a fresh build of encoder.go rather than trusting the submitted executable."""
    random.seed(7331)
    cases = [b"", bytes(range(256)), b"\x00" * 1025]
    for _ in range(500):
        length = random.randint(1, 1000)
        cases.append(bytes(random.randrange(256) for _ in range(length)))

    for i, input_bytes in enumerate(cases):
        expected_output = python_oracle(input_bytes)
        actual_output = run_and_check(rebuilt_binary, input_bytes, "Rebuilt Go program")
        assert actual_output == expected_output, (
            f"Freshly compiled encoder.go mismatched oracle on case #{i+1} "
            f"(length {len(input_bytes)})"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
