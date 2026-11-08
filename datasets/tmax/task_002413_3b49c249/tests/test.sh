#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import stat
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = '/home/user/log_classifier.py'
CLEAN_DIR = '/app/corpora/clean'
EVIL_DIR = '/app/corpora/evil'
HEADER = ['timestamp', 'user_id', 'LOGIN', 'LOGOUT', 'QUERY', 'EXPORT']


def run_classifier(filepath):
    try:
        return subprocess.run(
            ['python3', SCRIPT_PATH, filepath],
            capture_output=True,
            timeout=10,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail('Classifier timed out while processing a small CSV file.')


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"Script {SCRIPT_PATH} is not a regular file."


def test_clean_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory {CLEAN_DIR} missing."
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No clean files found in corpus."

    failed_files = []
    for f in clean_files:
        filepath = os.path.join(CLEAN_DIR, f)
        res = subprocess.run(['python3', SCRIPT_PATH, filepath], capture_output=True)
        if res.returncode != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory {EVIL_DIR} missing."
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No evil files found in corpus."

    failed_files = []
    for f in evil_files:
        filepath = os.path.join(EVIL_DIR, f)
        res = subprocess.run(['python3', SCRIPT_PATH, filepath], capture_output=True)
        if res.returncode != 1:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_files)}")


def policy_result(filepath):
    """Derive the required exit status directly from the stated policy."""
    with open(filepath, 'r', encoding='utf-8', newline='') as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            return 1
        if header != HEADER:
            return 1

        seen = set()
        for row in reader:
            if len(row) != len(HEADER):
                return 1
            timestamp, user_id = row[0], row[1]
            for event_type, details in zip(HEADER[2:], row[2:]):
                if details == '':
                    continue
                if '\r' in details or '\n' in details:
                    return 1
                key = (timestamp, user_id, event_type)
                if key in seen:
                    return 1
                seen.add(key)
    return 0


def encode_csv(rows):
    from io import StringIO
    out = StringIO(newline='')
    writer = csv.writer(out, lineterminator='\n')
    writer.writerow(HEADER)
    writer.writerows(rows)
    return out.getvalue()


def test_randomized_policy_cases_on_neutral_reused_path():
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix='audit-input-') as directory:
        # Every case is written to exactly the same randomly named neutral path,
        # so classification cannot be inferred from a clean/evil pathname.
        filepath = os.path.join(directory, uuid.uuid4().hex + '.csv')

        for round_number in range(5):
            token = uuid.uuid4().hex
            uid = str(rng.randrange(1000, 999999))
            timestamp = f"2026-09-{round_number + 1:02d}T12:{rng.randrange(60):02d}:00Z"
            timestamp2 = f"2026-10-{round_number + 1:02d}T13:{rng.randrange(60):02d}:00Z"

            # Valid quoted commas and quotes, multiple events in one row, and
            # policy-related words without actual control characters.
            clean_rows = [
                [timestamp, uid, f'accepted, token "{token}"', '', '', f'CR LF duplicate {token}'],
                [timestamp2, str(int(uid) + 1), '', 'Success', f'SELECT "{token}"', ''],
            ]

            event_index = rng.randrange(2, 6)
            lf_row = [timestamp, uid, '', '', '', '']
            lf_row[event_index] = f'{token} first line\nsecond line'

            cr_row = [timestamp2, uid, '', '', '', '']
            cr_row[event_index] = f'{token} left\rright'

            duplicate_a = [timestamp, uid, '', '', '', '']
            duplicate_b = [timestamp, uid, '', '', '', '']
            duplicate_a[event_index] = f'first benign value {token}'
            duplicate_b[event_index] = f'different benign value {token}'

            cases = [
                encode_csv(clean_rows),
                encode_csv([lf_row]),
                encode_csv([cr_row]),
                encode_csv([duplicate_a, duplicate_b]),
            ]
            rng.shuffle(cases)

            observed_expectations = set()
            for contents in cases:
                with open(filepath, 'w', encoding='utf-8', newline='') as handle:
                    handle.write(contents)

                expected = policy_result(filepath)
                observed_expectations.add(expected)
                actual = run_classifier(filepath)
                assert actual == expected, (
                    f'Classifier returned {actual}, expected {expected}, for a '
                    f'dynamically generated policy case.'
                )

            assert observed_expectations == {0, 1}
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
