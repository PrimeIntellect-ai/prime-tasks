#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

def test_config_string():
    config_path = "/home/user/config_string.txt"
    assert os.path.isfile(config_path), f"File {config_path} does not exist."
    with open(config_path, "r") as f:
        content = f.read().strip()
    assert content == "CFG-X9B2K1L7", f"Incorrect config string: {content}"

def test_audio_codes():
    audio_codes_path = "/home/user/audio_codes.txt"
    assert os.path.isfile(audio_codes_path), f"File {audio_codes_path} does not exist."
    with open(audio_codes_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected = ["4829", "1055", "9382", "4410"]
    assert lines == expected, f"Incorrect audio codes. Expected {expected}, got {lines}"

def test_bad_commit():
    bad_commit_path = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_path), f"File {bad_commit_path} does not exist."
    with open(bad_commit_path, "r") as f:
        commit_hash = f.read().strip()

    assert len(commit_hash) in (7, 40), f"Invalid commit hash length: {commit_hash}"

    # Verify the commit exists in the repository
    repo_path = "/home/user/telemetry-processor"
    result = subprocess.run(
        ["git", "cat-file", "-t", commit_hash],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0 and result.stdout.strip() == "commit", f"Commit {commit_hash} not found in repo."

    # Find the commit that introduced the anomalous A-to-B transformation.
    expected_result = subprocess.run(
        ["git", "log", "--format=%H", "--reverse", "-Ssed 's/A/B/g'", "v1.0..HEAD", "--", "telemetry_parser.sh"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    assert expected_result.returncode == 0, f"Could not identify regression commit: {expected_result.stderr}"
    introducing_commits = [line.strip() for line in expected_result.stdout.splitlines() if line.strip()]
    assert len(introducing_commits) == 1, f"Expected one regression-introducing commit, found {introducing_commits}"

    resolved_result = subprocess.run(
        ["git", "rev-parse", f"{commit_hash}^{{commit}}"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    assert resolved_result.returncode == 0, f"Could not resolve submitted commit {commit_hash}."
    assert resolved_result.stdout.strip() == introducing_commits[0], (
        f"Incorrect bad commit. Expected {introducing_commits[0]}, got {resolved_result.stdout.strip()}"
    )

def test_fuzz_equivalence():
    script_path = "/home/user/parse_telemetry.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    # We must checkout v1.0 and build the oracle if it doesn't exist, but the prompt says
    # Oracle path: /home/user/telemetry-processor/bin/telemetry_parser_v1.0
    oracle_path = "/home/user/telemetry-processor/bin/telemetry_parser_v1.0"

    # If the oracle doesn't exist at the exact path, we might need to compile it or it's already there.
    # We will assume it's there or we can fallback to running the script if we can't find it,
    # but the instructions say "Locate the oracle program at the exact path truth declares."
    assert os.path.isfile(oracle_path), f"Oracle {oracle_path} does not exist."
    assert os.access(oracle_path, os.X_OK), f"Oracle {oracle_path} is not executable."

    random.seed(42)
    charset = string.ascii_letters + string.digits + "!@#$%^&*()"

    N = 10000
    for i in range(N):
        length = random.randint(10, 50)
        chars = []
        for _ in range(length):
            if random.random() < 0.10:
                chars.append('\x00')
            else:
                chars.append(random.choice(charset))

        test_input = "".join(chars).encode('utf-8')

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=test_input,
                capture_output=True,
                timeout=2
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: {test_input!r}")

        # Run agent script
        try:
            agent_proc = subprocess.run(
                ["/bin/bash", script_path],
                input=test_input,
                capture_output=True,
                timeout=2
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {test_input!r}")

        assert agent_out == oracle_out, (
            f"Mismatch on input {test_input!r}.\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
