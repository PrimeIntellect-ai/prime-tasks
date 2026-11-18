#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import subprocess
import secrets
import string
import tempfile


def is_valid(token):
    if not token.startswith("SEC_"):
        return False
    xor_sum = 0
    for char in token:
        xor_sum ^= ord(char)
    return xor_sum == 0x7F


def test_fast_validator_exists_and_executable():
    rust_bin = "/home/user/fast_validator"
    assert os.path.exists(rust_bin), f"The fast_validator binary is missing at {rust_bin}."
    assert os.path.isfile(rust_bin), f"The path {rust_bin} is not a file."
    assert os.access(rust_bin, os.X_OK), f"The fast_validator binary at {rust_bin} is not executable."


def test_correctness():
    tokens_file = "/home/user/tokens.txt"
    valid_file = "/home/user/valid.txt"

    assert os.path.exists(valid_file), f"The output file {valid_file} is missing."

    expected_valid = []
    with open(tokens_file, 'r') as f:
        for line in f:
            token = line.strip()
            if not token:
                continue
            if token.startswith("SEC_"):
                xor_sum = 0
                for char in token:
                    xor_sum ^= ord(char)
                if xor_sum == 0x7F:
                    expected_valid.append(token)

    with open(valid_file, 'r') as f:
        actual_valid = [line.strip() for line in f if line.strip()]

    assert actual_valid == expected_valid, "The valid tokens produced do not match the expected valid tokens."


def test_mixed_prefixed_tokens():
    rust_bin = "/home/user/fast_validator"
    alphabet = string.ascii_letters + string.digits
    rng = secrets.SystemRandom()
    tokens = []

    # Generate valid SEC_ tokens independently from the submitted validator.
    while sum(1 for token in tokens if is_valid(token)) < 256:
        suffix = ''.join(rng.choice(alphabet) for _ in range(rng.randint(10, 20)))
        token = "SEC_" + suffix
        if is_valid(token):
            tokens.append(token)

    # Crucially, include many SEC_-prefixed tokens that fail the XOR constraint.
    while len(tokens) < 1280:
        suffix = ''.join(rng.choice(alphabet) for _ in range(rng.randint(10, 20)))
        token = "SEC_" + suffix
        if not is_valid(token):
            tokens.append(token)

    # Include ordinary non-prefixed invalid tokens as well.
    for _ in range(256):
        tokens.append(''.join(rng.choice(alphabet) for _ in range(rng.randint(10, 20))))

    rng.shuffle(tokens)
    expected_valid = [token for token in tokens if is_valid(token)]

    challenge_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', prefix='validator_challenge_', suffix='.txt', delete=False) as challenge:
            challenge_path = challenge.name
            for token in tokens:
                challenge.write(token + "\n")

        result = subprocess.run(
            [rust_bin, challenge_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"The fast_validator exited with code {result.returncode}: {result.stderr}"
        actual_valid = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert actual_valid == expected_valid, "The fast_validator does not enforce the SEC_ token XOR constraint."
    finally:
        if challenge_path is not None and os.path.exists(challenge_path):
            os.unlink(challenge_path)


def test_speedup():
    tokens_file = "/home/user/tokens.txt"
    oracle = "/app/api_oracle"
    rust_bin = "/home/user/fast_validator"
    eval_output = "/home/user/valid_eval.txt"

    # Measure Oracle Baseline (subset of 1000 tokens to extrapolate)
    start_baseline = time.time()
    subprocess.run(f"head -n 1000 {tokens_file} | xargs -I {{}} {oracle} {{}}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    baseline_time_per_1k = time.time() - start_baseline
    estimated_baseline_total = baseline_time_per_1k * 1000

    # Measure Agent Solution
    start_rust = time.time()
    subprocess.run(f"{rust_bin} {tokens_file} > {eval_output}", shell=True)
    rust_time = time.time() - start_rust

    speedup = estimated_baseline_total / rust_time
    assert speedup >= 50.0, f"Speedup {speedup:.2f}x is below the 50.0x threshold."

    # Verify eval output matches expected to ensure they didn't just write a no-op script
    expected_valid = []
    with open(tokens_file, 'r') as f:
        for line in f:
            token = line.strip()
            if not token:
                continue
            if token.startswith("SEC_"):
                xor_sum = 0
                for char in token:
                    xor_sum ^= ord(char)
                if xor_sum == 0x7F:
                    expected_valid.append(token)

    with open(eval_output, 'r') as f:
        actual_valid = [line.strip() for line in f if line.strip()]

    assert actual_valid == expected_valid, "The fast_validator did not produce the correct output during the speedup evaluation."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
