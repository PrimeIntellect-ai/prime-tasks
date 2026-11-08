#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import secrets
import string
import subprocess
import pytest


def test_sanitizer_exists():
    assert os.path.isfile("/home/user/sanitizer.py"), "Sanitizer script /home/user/sanitizer.py does not exist."


def test_sanitizer_adversarial_corpus():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), "Sanitizer script not found."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    assert os.path.isdir(clean_dir), f"Missing clean corpus directory at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory at {evil_dir}"

    clean_files = os.listdir(clean_dir)
    evil_files = os.listdir(evil_dir)

    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    clean_failed = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        # Pass the absolute path to test if the script correctly extracts the basename
        result = subprocess.run(
            ["python3", sanitizer_path, filepath],
            capture_output=True
        )
        # Clean files should be accepted (exit code 0)
        if result.returncode != 0:
            clean_failed.append(filename)

    evil_bypassed = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(
            ["python3", sanitizer_path, filepath],
            capture_output=True
        )
        # Evil files should be rejected (exit code 1)
        if result.returncode == 0:
            evil_bypassed.append(filename)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed)}")

    assert not errors, " | ".join(errors)


def test_randomized_boundary_and_basename_rules():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), "Sanitizer script not found."

    alphabet = string.ascii_letters + string.digits + "._-"

    def random_name(length):
        assert length >= 1
        return secrets.choice(string.ascii_letters) + "".join(
            secrets.choice(alphabet) for _ in range(length - 1)
        )

    def expected_status(argument):
        basename = os.path.basename(argument)
        return 0 if len(basename) < 16 and " " not in basename else 1

    nonce = secrets.token_hex(12)
    cases = []

    # Put valid basenames under the directory named "evil" and invalid basenames
    # under "clean" so a directory-based classifier cannot pass.
    for i in range(20):
        valid = random_name((1, 14, 15)[i % 3])
        too_long = random_name(16 + random.randrange(0, 20))
        with_space = random_name(3 + (i % 4)) + " " + random_name(2 + (i % 3))

        cases.append(os.path.join("/app/corpora/evil", valid))
        cases.append(os.path.join("/app/corpora/clean", too_long))
        cases.append(os.path.join("/app/corpora/clean", with_space))

    # Directory components, including spaces and excessive length, must be ignored.
    cases.extend([
        os.path.join("/tmp", nonce, "directory with spaces", random_name(15)),
        os.path.join("/tmp", "x" * 80, random_name(1)),
        os.path.join("/tmp", nonce, "directory with spaces", random_name(16)),
        os.path.join("/tmp", nonce, random_name(7) + " " + random_name(7)),
        random_name(15),
        random_name(16),
    ])

    for argument in cases:
        expected = expected_status(argument)
        result = subprocess.run(
            ["python3", sanitizer_path, argument],
            capture_output=True,
            timeout=5,
        )
        assert result.returncode == expected, (
            f"Wrong exit status for {argument!r} (basename {os.path.basename(argument)!r}): "
            f"expected {expected}, got {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
