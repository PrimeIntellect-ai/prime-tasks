#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/validate_sshd.py"
BASELINE = [
    ("MaxAuthTries", "3"),
    ("ClientAliveInterval", "300"),
    ("PermitEmptyPasswords", "no"),
]


def run_validator(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    )


def random_case(key):
    return "".join(
        ch.upper() if secrets.randbelow(2) else ch.lower()
        for ch in key
    )


def valid_lines():
    lines = []
    for key, value in BASELINE:
        leading = " " * secrets.randbelow(4)
        separator = "\t" if secrets.randbelow(2) else " " * (1 + secrets.randbelow(6))
        trailing = " " * secrets.randbelow(4)
        lines.append(f"{leading}{random_case(key)}{separator}{value}{trailing}")
    random.SystemRandom().shuffle(lines)
    return lines


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    clean_rejected = []
    for cf in clean_files:
        res = run_validator(cf)
        if res.returncode != 0:
            clean_rejected.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        res = run_validator(ef)
        if res.returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not errors, " | ".join(errors)


def test_generated_hidden_configurations():
    cases = []

    # Valid configurations use randomized casing, spacing, ordering, filenames,
    # and unrelated safe directives so path- or corpus-specific solutions fail.
    for _ in range(8):
        lines = valid_lines()
        lines.extend(["", "# ordinary safe comment", "Port 22"])
        cases.append((lines, 0, "valid randomized configuration"))

    # Every required setting is independently tested as missing and incorrect.
    wrong_values = {
        "MaxAuthTries": "4",
        "ClientAliveInterval": "301",
        "PermitEmptyPasswords": "yes",
    }
    for missing_key, _ in BASELINE:
        lines = [f"{key} {value}" for key, value in BASELINE if key != missing_key]
        cases.append((lines, 1, f"missing {missing_key}"))

    for wrong_key, _ in BASELINE:
        lines = [
            f"{key} {wrong_values[key] if key == wrong_key else value}"
            for key, value in BASELINE
        ]
        cases.append((lines, 1, f"incorrect {wrong_key}"))

    # A commented-out setting must not satisfy the policy.
    for commented_key, _ in BASELINE:
        lines = [
            (f"# {key} {value}" if key == commented_key else f"{key} {value}")
            for key, value in BASELINE
        ]
        cases.append((lines, 1, f"commented-out {commented_key}"))

    # Exercise each forbidden character in comments and non-comment content.
    for metachar in ";|&`":
        lines = [f"{key} {value}" for key, value in BASELINE]
        lines.append(f"# unsafe {metachar} content")
        cases.append((lines, 1, f"metacharacter {metachar!r} in comment"))

        lines = [f"{key} {value}" for key, value in BASELINE]
        lines.append(f"Banner /tmp/banner{metachar}payload")
        cases.append((lines, 1, f"metacharacter {metachar!r} in directive"))

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sshd-policy-") as directory:
        failures = []
        for lines, expected, description in cases:
            filename = secrets.token_hex(12) + ".cfg"
            path = os.path.join(directory, filename)
            with open(path, "w", encoding="utf-8") as config:
                config.write("\n".join(lines) + "\n")

            result = run_validator(path)
            if result.returncode != expected:
                failures.append(
                    f"{description}: expected exit {expected}, got {result.returncode}"
                )

        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
