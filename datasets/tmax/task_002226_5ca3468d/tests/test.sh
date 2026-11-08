#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import string
import subprocess

import pytest

ROOT = "/app/vendored/api-signer"
AGENT_BIN = "/home/user/sign"
ORACLE_BIN = "/app/oracle_signer"
REBUILT_BIN = "/tmp/verifier-rebuilt-sign"


def run_binary(path, payload):
    try:
        proc = subprocess.run(
            [path, payload],
            capture_output=True,
            text=True,
            check=True,
            timeout=2,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"{path} failed on input {payload!r}: {exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out on input {payload!r}")
    return proc.stdout.strip()


def expected_hash(payload):
    modulus = 1_000_000_009
    base = 31
    value = 0
    power = 1
    for byte in payload.encode("utf-8"):
        value = (value + byte * power) % modulus
        power = (power * base) % modulus
    return str(value)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


@pytest.fixture(scope="session", autouse=True)
def verify_and_build_source():
    required = [
        os.path.join(ROOT, "go.mod"),
        os.path.join(ROOT, "pkg/signer/sign.go"),
        os.path.join(ROOT, "pkg/hashmath/calc.go"),
        os.path.join(ROOT, "cmd/sign/main.go"),
    ]
    for path in required:
        assert os.path.isfile(path), f"Required vendored source file is missing: {path}"

    test_proc = subprocess.run(
        ["go", "test", "./..."],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert test_proc.returncode == 0, (
        "The vendored Go module still fails to compile or test:\n"
        + test_proc.stdout
        + test_proc.stderr
    )

    build_proc = subprocess.run(
        ["go", "build", "-o", REBUILT_BIN, "./cmd/sign"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build_proc.returncode == 0, (
        "Could not build the repaired vendored command:\n"
        + build_proc.stdout
        + build_proc.stderr
    )
    assert os.path.isfile(REBUILT_BIN) and os.access(REBUILT_BIN, os.X_OK)


def test_agent_executable_exists():
    assert os.path.exists(AGENT_BIN), f"Agent executable not found at {AGENT_BIN}"
    assert os.path.isfile(AGENT_BIN), f"{AGENT_BIN} is not a file"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent executable {AGENT_BIN} is not executable"


def test_agent_is_built_from_vendored_go_module_and_not_oracle_copy():
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert sha256(AGENT_BIN) != sha256(ORACLE_BIN), "Agent executable is a byte-for-byte copy of the oracle"

    info = subprocess.run(
        ["go", "version", "-m", AGENT_BIN],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert info.returncode == 0, f"Final executable is not a valid Go executable: {info.stderr}"
    metadata = info.stdout
    assert "api-signer/cmd/sign" in metadata, (
        "Final executable was not built as the vendored api-signer command:\n" + metadata
    )
    assert "mod\tapi-signer" in metadata, (
        "Final executable does not identify the vendored api-signer module:\n" + metadata
    )


def test_repaired_source_and_final_binary_match_derived_answers_without_oracle():
    rng = random.Random(9137)
    chars = string.ascii_letters + string.digits + " _-.:/"
    payloads = ["", "a", "testpayload123", "with spaces", "API-Signer_2026"]
    for _ in range(75):
        length = rng.randint(1, 160)
        payloads.append("".join(rng.choices(chars, k=length)))

    hidden_oracle = "/tmp/oracle_signer.hidden-by-verifier"
    if os.path.exists(hidden_oracle):
        os.unlink(hidden_oracle)
    os.rename(ORACLE_BIN, hidden_oracle)
    try:
        for payload in payloads:
            expected = expected_hash(payload)
            assert run_binary(REBUILT_BIN, payload) == expected, (
                f"Rebuilt vendored source produced the wrong checksum for {payload!r}"
            )
            assert run_binary(AGENT_BIN, payload) == expected, (
                f"Final executable produced the wrong checksum for {payload!r}"
            )
    finally:
        os.rename(hidden_oracle, ORACLE_BIN)


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary {ORACLE_BIN} is not executable"

    random.seed(42)
    chars = string.ascii_letters + string.digits

    for _ in range(100):
        length = random.randint(10, 100)
        payload = "".join(random.choices(chars, k=length))
        oracle_output = run_binary(ORACLE_BIN, payload)
        agent_output = run_binary(AGENT_BIN, payload)
        assert agent_output == oracle_output, (
            f"Output mismatch on input {payload!r}.\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
