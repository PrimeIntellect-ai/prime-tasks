#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

LOG_PATH = '/home/user/security.log'
OUTPUT_PATH = '/home/user/compromised_tokens.txt'
SOURCE_PATH = '/home/user/auditor.c'
BINARY_PATH = '/home/user/auditor'
REBUILT_PATH = '/tmp/auditor_rebuilt'


def get_expected_tokens(log_path):
    expected_tokens = []
    with open(log_path, 'r') as f:
        for line in f:
            if "REASON=SANDBOX_VIOLATION" in line:
                parts = line.strip().split('|')
                for part in parts:
                    part = part.strip()
                    if part.startswith("TOKEN="):
                        token = part.split('=')[1].strip()
                        if len(token) == 16:
                            try:
                                digit_sum = sum(int(char, 16) for char in token)
                                if digit_sum % 3 == 0:
                                    expected_tokens.append(token.lower())
                            except ValueError:
                                pass
    return expected_tokens


def read_actual_tokens():
    assert os.path.exists(OUTPUT_PATH), f"The output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def run_and_check(executable, expected):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [executable], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    actual = read_actual_tokens()
    assert actual == expected, (
        f"The contents of {OUTPUT_PATH} are incorrect.\n"
        f"Expected: {expected}\nFound: {actual}"
    )


def make_token(valid, used):
    while True:
        token = ''.join(secrets.choice('0123456789abcdef') for _ in range(16))
        if token not in used and ((sum(int(c, 16) for c in token) % 3 == 0) == valid):
            used.add(token)
            return token


def make_log():
    used = set()
    rows = []
    timestamp = 1800000000
    for _ in range(4):
        token = make_token(True, used)
        rows.append(f"{timestamp} | ACTION=EXEC | STATUS=DENIED | REASON=SANDBOX_VIOLATION | TOKEN={token} | COMMAND=/bin/sh")
        timestamp += 1
    for _ in range(3):
        token = make_token(False, used)
        rows.append(f"{timestamp} | ACTION=EXEC | STATUS=DENIED | REASON=SANDBOX_VIOLATION | TOKEN={token} | COMMAND=/bin/bash")
        timestamp += 1
    for _ in range(3):
        token = make_token(True, used)
        rows.append(f"{timestamp} | ACTION=EXEC | STATUS=DENIED | REASON=TIMEOUT | TOKEN={token} | COMMAND=sleep 10")
        timestamp += 1
    random.SystemRandom().shuffle(rows)
    return '\n'.join(rows) + '\n'


def test_compromised_tokens_output_and_auditor_program():
    assert os.path.exists(LOG_PATH), f"The input log file {LOG_PATH} is missing."
    assert os.path.isfile(SOURCE_PATH), f"The required C source file {SOURCE_PATH} is missing."
    assert os.path.isfile(BINARY_PATH), f"The required executable {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY_PATH} is not a compiled executable."

    compile_result = subprocess.run(
        ['gcc', SOURCE_PATH, '-o', REBUILT_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"{SOURCE_PATH} does not compile successfully.\n"
        f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
    )

    with open(LOG_PATH, 'rb') as f:
        original_log = f.read()

    try:
        # Preserve the original verifier's exact behavioral assertion.
        original_expected = get_expected_tokens(LOG_PATH)
        run_and_check(BINARY_PATH, original_expected)

        # Exercise both the submitted binary and a fresh build on unpredictable logs.
        for _ in range(2):
            generated_log = make_log()
            with open(LOG_PATH, 'w') as f:
                f.write(generated_log)
            expected = get_expected_tokens(LOG_PATH)
            run_and_check(BINARY_PATH, expected)
            run_and_check(REBUILT_PATH, expected)
    finally:
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)

    # Leave and verify the requested output for the original security log.
    original_expected = get_expected_tokens(LOG_PATH)
    run_and_check(BINARY_PATH, original_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
