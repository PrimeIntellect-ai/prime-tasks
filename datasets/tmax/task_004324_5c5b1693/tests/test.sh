#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile
import zlib

import pytest

SCRIPT_PATH = "/home/user/validator.py"
MASTER_KEY = 0xB2A5


def run_validator(filepath):
    assert os.path.isfile(SCRIPT_PATH), f"Validator script missing at {SCRIPT_PATH}"

    result = subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=5
    )
    return result.stdout.strip()


def test_clean_corpus_accepted():
    clean_dir = "/app/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(files) > 0, f"Clean corpus directory is empty: {clean_dir}"

    failed_files = []
    for f in files:
        filepath = os.path.join(clean_dir, f)
        output = run_validator(filepath)
        if output != "ACCEPT":
            failed_files.append((f, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(files)} clean files were not ACCEPTED.\n"
        error_msg += "Offending files:\n"
        for f, out in failed_files[:5]:
            error_msg += f" - {f} (Output: {out})\n"
        pytest.fail(error_msg)


def test_evil_corpus_rejected():
    evil_dir = "/app/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(files) > 0, f"Evil corpus directory is empty: {evil_dir}"

    failed_files = []
    for f in files:
        filepath = os.path.join(evil_dir, f)
        output = run_validator(filepath)
        if output != "REJECT":
            failed_files.append((f, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(files)} evil files bypassed rejection.\n"
        error_msg += "Offending files:\n"
        for f, out in failed_files[:5]:
            error_msg += f" - {f} (Output: {out})\n"
        pytest.fail(error_msg)


def expected_token(username):
    crc = zlib.crc32(username.encode("utf-8")) & 0xFFFF
    return f"{crc ^ MASTER_KEY:04x}"


def random_username():
    alphabet = string.ascii_letters + string.digits + "_-+."
    return "u" + "".join(secrets.choice(alphabet) for _ in range(random.randint(8, 40)))


def test_fresh_generated_corpora():
    cases = []
    with tempfile.TemporaryDirectory(prefix="token-audit-") as directory:
        # Create fresh valid and forged files at opaque, randomized paths. Expected
        # tokens are independently recomputed using the specified algorithm.
        for should_accept in ([True] * 6 + [False] * 6):
            entries = []
            for _ in range(random.randint(2, 12)):
                username = random_username()
                entries.append([username, expected_token(username)])

            if not should_accept:
                index = random.randrange(len(entries))
                valid_value = int(entries[index][1], 16)
                forged_value = valid_value ^ (1 << random.randrange(16))
                entries[index][1] = f"{forged_value:04x}"

            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "w", encoding="utf-8") as handle:
                for username, token in entries:
                    handle.write(f"{username}:{token}\n")
            cases.append((path, "ACCEPT" if should_accept else "REJECT"))

        random.shuffle(cases)
        failures = []
        for path, expected in cases:
            output = run_validator(path)
            if output != expected:
                failures.append((os.path.basename(path), expected, output))

        if failures:
            message = f"{len(failures)} fresh generated token files were misclassified.\n"
            for name, expected, output in failures[:5]:
                message += f" - {name}: expected {expected}, got {output!r}\n"
            pytest.fail(message)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
