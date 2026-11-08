#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import secrets
import stat
import subprocess
import tempfile
from datetime import datetime, timezone

import pytest

SCRIPT_PATH = "/home/user/filter_logs.py"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
GENERATOR_PATH = "/app/fake_metric_gen"


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."


def run_filter_script(input_csv_path):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, input_csv_path],
        capture_output=True,
        text=True
    )
    return result.returncode, result.stdout, result.stderr


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Directory {EVIL_CORPUS_DIR} does not exist."
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, f"No CSV files found in {EVIL_CORPUS_DIR}."

    bypassed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        returncode, stdout, stderr = run_filter_script(filepath)

        if returncode != 0:
            bypassed_files.append((filename, f"Script exited with code {returncode}"))
            continue

        lines = stdout.strip().split('\n')
        # Should only contain the header
        if len(lines) > 1:
            bypassed_files.append((filename, f"Failed to reject {len(lines)-1} evil rows"))

    if bypassed_files:
        details = ", ".join([f"{f}: {reason}" for f, reason in bypassed_files])
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed: {details}")


def test_clean_corpus_preserved():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Directory {CLEAN_CORPUS_DIR} does not exist."
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    assert len(clean_files) > 0, f"No CSV files found in {CLEAN_CORPUS_DIR}."

    modified_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)

        with open(filepath, 'r') as f:
            expected_content = f.read().strip()

        returncode, stdout, stderr = run_filter_script(filepath)

        if returncode != 0:
            modified_files.append((filename, f"Script exited with code {returncode}"))
            continue

        actual_content = stdout.strip()
        if actual_content != expected_content:
            modified_files.append((filename, "Output did not match input exactly"))

    if modified_files:
        details = ", ".join([f"{f}: {reason}" for f, reason in modified_files])
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean files modified: {details}")


def _make_hidden_csv(directory, malicious_flags):
    rng = random.SystemRandom()
    records = []
    for is_malicious in malicious_flags:
        ts = rng.randint(978307200, 2082758399)
        uid = rng.randint(0, 2_000_000_000)
        malicious_value = (ts ^ uid) % 9973
        if is_malicious:
            value = malicious_value
        else:
            delta = rng.randint(1, 50000)
            value = malicious_value + delta
        timestamp_iso = datetime.fromtimestamp(ts, timezone.utc).isoformat().replace('+00:00', 'Z')
        records.append((is_malicious, [timestamp_iso, str(uid), str(value)]))

    rng.shuffle(records)
    path = os.path.join(directory, secrets.token_hex(16) + '.csv')
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp_iso', 'user_id', 'metric_value'])
        writer.writerows(row for _, row in records)

    expected = [['timestamp_iso', 'user_id', 'metric_value']]
    expected.extend(row for is_malicious, row in records if not is_malicious)
    return path, expected


def test_random_hidden_inputs_use_timestamp_and_generator_formula():
    # The submitted sanitizer must contain the recovered mathematics rather than
    # using the generator once per input row at runtime.
    assert os.path.isfile(GENERATOR_PATH)
    generator_mode = stat.S_IMODE(os.stat(GENERATOR_PATH).st_mode)
    with open(GENERATOR_PATH, 'rb') as f:
        generator_bytes = f.read()

    with tempfile.TemporaryDirectory(prefix='sanitizer-hidden-') as directory:
        cases = [
            [True] * 137,
            [False] * 137,
            [True] * 91 + [False] * 93,
        ]
        generated = [_make_hidden_csv(directory, flags) for flags in cases]

        os.unlink(GENERATOR_PATH)
        try:
            for path, expected_rows in generated:
                result = subprocess.run(
                    ['python3', SCRIPT_PATH, path],
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                assert result.returncode == 0, (
                    f"Sanitizer failed on hidden input with code {result.returncode}: "
                    f"{result.stderr}"
                )
                actual_rows = list(csv.reader(io.StringIO(result.stdout)))
                assert actual_rows == expected_rows, (
                    "Sanitizer did not filter randomized rows according to the "
                    "timestamp/user_id generator formula"
                )
        finally:
            restore_path = GENERATOR_PATH + '.restore-' + secrets.token_hex(8)
            with open(restore_path, 'wb') as f:
                f.write(generator_bytes)
            os.chmod(restore_path, generator_mode)
            os.replace(restore_path, GENERATOR_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
