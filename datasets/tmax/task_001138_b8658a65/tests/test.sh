#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitize.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"

def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Sanitize script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"

def run_sanitize_script(filepath):
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True
    )
    return result.stdout, result.stderr, result.returncode

def test_clean_corpus_preserved():
    if not os.path.exists(CLEAN_CORPUS_DIR):
        pytest.skip(f"Clean corpus dir missing: {CLEAN_CORPUS_DIR}")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    failed_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            original_content = f.read()

        stdout, stderr, rc = run_sanitize_script(filepath)

        if stdout != original_content:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified. Offending files: {', '.join(failed_files)}")

def compute_expected_sanitized_output(original_content):
    expected_lines = []
    for line in original_content.splitlines(keepends=True):
        stripped = line.strip('\n')
        parts = stripped.split(' ')
        if len(parts) != 3:
            expected_lines.append(line)
            continue

        ts, pressure, status = parts

        # Rule 1: Drop overload timestamps
        if ts in ["1715000004", "1715000005", "1715000006"]:
            continue

        # Rule 2: Drop scientific notation
        if 'e' in pressure or 'E' in pressure:
            continue

        # Rule 3: Truncate fractional part to exactly 4 decimal places
        if '.' in pressure:
            integer_part, fractional_part = pressure.split('.', 1)
            if len(fractional_part) > 4:
                pressure = f"{integer_part}.{fractional_part[:4]}"

        # Reconstruct line preserving original spacing logic
        # The spec says "preserving original spacing and format" for passed lines,
        # but for truncated lines it should be exactly the reconstructed string.
        # We assume single space separation as per "space-separated" spec.
        expected_lines.append(f"{ts} {pressure} {status}\n")

    return "".join(expected_lines)

def test_evil_corpus_sanitized():
    if not os.path.exists(EVIL_CORPUS_DIR):
        pytest.skip(f"Evil corpus dir missing: {EVIL_CORPUS_DIR}")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    failed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            original_content = f.read()

        expected_output = compute_expected_sanitized_output(original_content)
        stdout, stderr, rc = run_sanitize_script(filepath)

        if stdout != expected_output:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_files)}")

def random_status():
    return "S" + secrets.token_hex(6).upper()

def random_safe_timestamp():
    # Use unpredictable timestamps well outside the overload interval.
    return str(1716000000 + secrets.randbelow(1000000))

def random_digits(count):
    return ''.join(str(secrets.randbelow(10)) for _ in range(count))

def expected_for_generated(lines):
    output = []
    for ts, pressure, status in lines:
        if 1715000004 <= int(ts) <= 1715000006:
            continue
        if 'e' in pressure or 'E' in pressure:
            continue
        if '.' in pressure:
            integer_part, fractional_part = pressure.split('.', 1)
            if len(fractional_part) > 4:
                pressure = integer_part + '.' + fractional_part[:4]
        output.append(f"{ts} {pressure} {status}\n")
    return ''.join(output)

def test_randomized_adversarial_inputs():
    # Fresh paths, values, statuses, and ordering prevent solutions that branch on
    # the shipped corpus directory/content or print its two known outputs.
    with tempfile.TemporaryDirectory(prefix="sanitize-generated-") as tempdir:
        for trial in range(12):
            lines = []

            # Unchanged records with several legal pressure representations.
            lines.append((random_safe_timestamp(), str(10 + secrets.randbelow(900)), random_status()))
            lines.append((random_safe_timestamp(), f"{10 + secrets.randbelow(900)}.{random_digits(1 + secrets.randbelow(4))}", random_status()))
            lines.append((random_safe_timestamp(), f"-{1 + secrets.randbelow(90)}.{random_digits(4)}", random_status()))

            # Precision records whose unpredictable suffixes must be truncated.
            lines.append((random_safe_timestamp(), f"{10 + secrets.randbelow(900)}.{random_digits(5 + secrets.randbelow(8))}", random_status()))
            lines.append((random_safe_timestamp(), f"-{1 + secrets.randbelow(90)}.{random_digits(6 + secrets.randbelow(6))}", random_status()))

            # Both scientific-notation spellings must be removed.
            lines.append((random_safe_timestamp(), f"{1 + secrets.randbelow(9)}.{random_digits(2)}e+{1 + secrets.randbelow(8)}", random_status()))
            lines.append((random_safe_timestamp(), f"{1 + secrets.randbelow(9)}.{random_digits(3)}E-{1 + secrets.randbelow(8)}", random_status()))

            # Exercise every inclusive timestamp in the video-derived window with
            # unpredictable otherwise-safe records.
            for attack_ts in (1715000004, 1715000005, 1715000006):
                lines.append((str(attack_ts), f"{100 + secrets.randbelow(800)}.{random_digits(4)}", random_status()))

            # Nearby timestamps establish both boundaries are exact.
            lines.append(("1715000003", f"{100 + secrets.randbelow(800)}.{random_digits(4)}", random_status()))
            lines.append(("1715000007", f"{100 + secrets.randbelow(800)}.{random_digits(5)}", random_status()))

            # Shuffle without relying on the non-cryptographic random module.
            decorated = [(secrets.randbits(128), item) for item in lines]
            lines = [item for _, item in sorted(decorated, key=lambda pair: pair[0])]

            original = ''.join(f"{ts} {pressure} {status}\n" for ts, pressure, status in lines)
            expected = expected_for_generated(lines)
            filepath = os.path.join(tempdir, f"case-{trial}-{secrets.token_hex(8)}.log")
            with open(filepath, 'w') as f:
                f.write(original)

            stdout, stderr, rc = run_sanitize_script(filepath)
            assert stdout == expected, f"Incorrect output for randomized adversarial case {trial}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
