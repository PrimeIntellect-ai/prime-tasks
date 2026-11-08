#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import shutil
import string
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/reference_encoder"
AGENT_PATH = "/home/user/monitor_fixed"
SOURCE_PATH = "/home/user/metric_agent/encoder.c"
NUM_TESTS = 1000
TIMEOUT_SECONDS = 2.0


def run_as_user():
    account = pwd.getpwnam("user")
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def run_candidate(path, input_data):
    try:
        return subprocess.run(
            [path],
            input=input_data,
            capture_output=True,
            timeout=TIMEOUT_SECONDS,
            preexec_fn=run_as_user,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"Candidate {path} timed out (infinite loop?) on input of length "
            f"{len(input_data)}. Input preview: {input_data[:100]!r}..."
        )


def test_agent_binary_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent binary {AGENT_PATH} does not exist."
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable."
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT_PATH} is not a compiled ELF binary."


def test_repository_source_exists_and_builds():
    assert os.path.isfile(SOURCE_PATH), f"Repository source {SOURCE_PATH} does not exist."
    result = subprocess.run(
        ["gcc", "-O2", SOURCE_PATH, "-o", "/tmp/rebuilt_monitor"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Repository source failed to compile:\n{result.stderr}"
    os.chmod("/tmp/rebuilt_monitor", 0o755)


def test_submission_is_not_reference_binary():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} does not exist."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable."
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "monitor_fixed is a byte-identical copy of the vendor binary."


def test_fuzz_equivalence():
    assert os.path.isfile("/tmp/rebuilt_monitor"), "Rebuilt repository binary is missing."

    random.seed(42)
    charset = string.ascii_letters + string.digits + string.punctuation + " \t\n"
    cases = []
    for _ in range(NUM_TESTS):
        length = random.randint(1, 1024)
        if random.random() < 0.3:
            char = random.choice(charset)
            input_data = (char * length).encode("utf-8")
        else:
            input_data = "".join(random.choice(charset) for _ in range(length)).encode("utf-8")
        cases.append(input_data)

    expected = []
    for input_data in cases:
        try:
            proc = subprocess.run(
                [ORACLE_PATH],
                input=input_data,
                capture_output=True,
                timeout=TIMEOUT_SECONDS,
                check=True,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle binary timed out on input of length {len(input_data)}.")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle binary failed with return code {e.returncode}.")
        expected.append(proc.stdout)

    # Make the vendor executable unavailable while exercising submissions, so a
    # wrapper that delegates to /app/reference_encoder cannot satisfy the tests.
    hidden_dir = tempfile.mkdtemp(prefix="verifier-oracle-")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "reference_encoder")
    os.rename(ORACLE_PATH, hidden_oracle)
    try:
        for i, (input_data, oracle_output) in enumerate(zip(cases, expected)):
            for candidate in (AGENT_PATH, "/tmp/rebuilt_monitor"):
                proc = run_candidate(candidate, input_data)
                assert proc.returncode == 0, (
                    f"Candidate {candidate} failed with return code {proc.returncode} "
                    f"on fuzz case {i}, input length {len(input_data)}."
                )
                assert proc.stdout == oracle_output, (
                    f"Output mismatch from {candidate} on fuzz case {i}, input length "
                    f"{len(input_data)}.\nInput preview: {input_data[:100]!r}...\n"
                    f"Expected: {oracle_output[:100]!r}...\nGot: {proc.stdout[:100]!r}..."
                )
    finally:
        os.rename(hidden_oracle, ORACLE_PATH)
        shutil.rmtree(hidden_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
