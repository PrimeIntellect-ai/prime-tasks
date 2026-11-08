#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import string
import tempfile
import subprocess
import sys
import pytest

VENDORED_DIR = "/app/vendored/xxHash-0.8.1"
XXHSUM_PATH = os.path.join(VENDORED_DIR, "xxhsum")
ORACLE_PATH = "/tests/oracle_etl"
AGENT_SCRIPT = "/home/user/run_etl.sh"
INVOCATION_LOG = "/tmp/xxhsum_invocations"

def test_xxhash_compiles():
    """Test that the vendored xxHash tool compiles and computes XXH32 correctly."""
    clean_proc = subprocess.run(["make", "clean"], cwd=VENDORED_DIR, capture_output=True)
    assert clean_proc.returncode == 0, f"make clean failed: {clean_proc.stderr.decode()}"

    make_proc = subprocess.run(["make", "xxhsum"], cwd=VENDORED_DIR, capture_output=True)
    assert make_proc.returncode == 0, f"make xxhsum failed: {make_proc.stderr.decode()}"

    assert os.path.isfile(XXHSUM_PATH), "xxhsum binary not found after make"
    with open(XXHSUM_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "xxhsum is not a compiled ELF binary"

    vectors = [
        (b"", "02cc5d05"),
        (b"a", "550d7456"),
        (b"test", "3e2023cf"),
        (b"alice_99", "6a5a2988"),
    ]
    for payload, expected in vectors:
        test_run = subprocess.run([XXHSUM_PATH, "-H0"], input=payload, capture_output=True)
        assert test_run.returncode == 0, f"xxhsum -H0 failed: {test_run.stderr.decode()}"
        tokens = test_run.stdout.decode().split()
        assert tokens and tokens[0] == expected, (
            f"incorrect XXH32 for {payload!r}: expected {expected}, got {test_run.stdout!r}"
        )

def generate_random_jsonl(num_lines):
    lines = []
    for _ in range(num_lines):
        record = {}
        if random.random() > 0.1:
            user_id_len = random.randint(1, 20)
            record["user_id"] = "".join(
                random.choices(string.ascii_letters + string.digits, k=user_id_len)
            )

        if random.random() > 0.1:
            amount = random.uniform(-500.0, 2000.0)
            if random.random() > 0.8:
                record["amount"] = f"{amount:.4f}"
            else:
                record["amount"] = amount

        lines.append(json.dumps(record))
    return "\n".join(lines) + "\n"

def install_xxhsum_probe():
    """Wrap the compiled utility so ETL invocations are observable."""
    real_path = XXHSUM_PATH + ".real"
    if os.path.exists(real_path):
        os.remove(real_path)
    os.rename(XXHSUM_PATH, real_path)
    with open(XXHSUM_PATH, "w") as f:
        f.write("#!/bin/sh\n")
        f.write(f"printf '1\\n' >> {INVOCATION_LOG}\n")
        f.write(f"exec '{real_path}' \"$@\"\n")
    os.chmod(XXHSUM_PATH, 0o755)
    if os.path.exists(INVOCATION_LOG):
        os.remove(INVOCATION_LOG)

def test_fuzz_equivalence():
    """Test the agent ETL against oracle-derived answers without exposing the oracle at execution time."""
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

    random.seed(42)
    cases = []

    # Derive every expected answer first. The oracle is then removed before any
    # submitted artifact is executed, preventing runtime delegation to it.
    for i in range(100):
        num_lines = random.randint(10, 1000)
        jsonl_data = generate_random_jsonl(num_lines)

        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".jsonl") as tmp:
            tmp.write(jsonl_data)
            tmp_path = tmp.name

        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_PATH, tmp_path], capture_output=True, text=True
        )
        if oracle_proc.returncode != 0:
            os.remove(tmp_path)
            pytest.fail(f"Oracle failed on input {i}: {oracle_proc.stderr}")
        cases.append((i, jsonl_data, tmp_path, oracle_proc.stdout))

    os.remove(ORACLE_PATH)
    install_xxhsum_probe()

    try:
        for i, jsonl_data, tmp_path, oracle_out in cases:
            agent_proc = subprocess.run(
                ["/bin/bash", AGENT_SCRIPT, tmp_path], capture_output=True, text=True
            )
            assert agent_proc.returncode == 0, (
                f"Agent script failed on input {i}: {agent_proc.stderr}"
            )

            if oracle_out != agent_proc.stdout:
                pytest.fail(
                    f"Output mismatch on fuzz iteration {i}.\n\nInput (first 5 lines):\n"
                    + "\n".join(jsonl_data.splitlines()[:5])
                    + f"\n\nExpected output (first 500 chars):\n{oracle_out[:500]}\n\n"
                    + f"Actual output (first 500 chars):\n{agent_proc.stdout[:500]}"
                )

        assert os.path.isfile(INVOCATION_LOG) and os.path.getsize(INVOCATION_LOG) > 0, (
            "The ETL pipeline did not invoke the compiled vendored xxhsum utility"
        )
    finally:
        for _, _, tmp_path, _ in cases:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
