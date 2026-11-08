#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
import tempfile
import pytest

CLEAN_CORPUS_DIR = '/app/corpora/clean/'
EVIL_CORPUS_DIR = '/app/corpora/evil/'
GO_SCRIPT_PATH = '/home/user/graph_validator.go'


def run_validator(csv_path):
    """Runs the student's Go script against a CSV file and returns the output."""
    if not os.path.isfile(GO_SCRIPT_PATH):
        pytest.fail(f"Go script not found at {GO_SCRIPT_PATH}")

    try:
        result = subprocess.run(
            ['go', 'run', GO_SCRIPT_PATH, csv_path],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1
    except Exception as e:
        return f"ERROR: {str(e)}", -1


def test_graph_validator_clean_corpus():
    """Verify that the script ACCEPTs all clean files."""
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    if not clean_files:
        pytest.fail("No CSV files found in clean corpus.")

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        output, retcode = run_validator(filepath)
        if output != "ACCEPT" or retcode != 0:
            failed_files.append((filename, output, retcode))

    if failed_files:
        details = ", ".join([f"{f} (out: {o}, code: {c})" for f, o, c in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected or failed: {details}")


def test_graph_validator_evil_corpus():
    """Verify that the script REJECTs all evil files."""
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    if not evil_files:
        pytest.fail("No CSV files found in evil corpus.")

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        output, retcode = run_validator(filepath)
        if output != "REJECT" or retcode != 0:
            failed_files.append((filename, output, retcode))

    if failed_files:
        details = ", ".join([f"{f} (out: {o}, code: {c})" for f, o, c in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed or failed: {details}")


def expected_result(rows):
    allowed = {
        ('User', 'Account', 'OWNS'),
        ('Account', 'Transaction', 'SENDS'),
        ('Transaction', 'Account', 'RECEIVES'),
    }
    sends = set()
    receives = set()

    for row in rows:
        if len(row) != 5:
            return 'REJECT'
        source_id, source_type, target_id, target_type, relation = row
        if (source_type, target_type, relation) not in allowed:
            return 'REJECT'
        if source_id == target_id:
            return 'REJECT'
        if relation == 'SENDS':
            sends.add((source_id, target_id))
        elif relation == 'RECEIVES':
            receives.add((target_id, source_id))

    if sends.intersection(receives):
        return 'REJECT'
    return 'ACCEPT'


def ident(prefix):
    return prefix + secrets.token_hex(10)


def valid_chain():
    user = ident('u')
    source_account = ident('a')
    transaction = ident('t')
    destination_account = ident('a')
    return [
        [user, 'User', source_account, 'Account', 'OWNS'],
        [source_account, 'Account', transaction, 'Transaction', 'SENDS'],
        [transaction, 'Transaction', destination_account, 'Account', 'RECEIVES'],
    ]


def test_graph_validator_generated_neutral_paths():
    """Exercise schema and topology rules on undisclosed, neutral file paths."""
    cases = []

    for _ in range(5):
        rows = valid_chain()
        if secrets.randbits(1):
            rows.extend(valid_chain())
        random.SystemRandom().shuffle(rows)
        cases.append(rows)

    u, a = ident('u'), ident('a')
    cases.append([[u, 'User', a, 'Account', 'LOVES']])

    u, a = ident('u'), ident('a')
    cases.append([[u, 'Alien', a, 'Account', 'OWNS']])

    a, t = ident('a'), ident('t')
    cases.append([[a, 'Account', t, 'Account', 'SENDS']])

    same = ident('node')
    cases.append([[same, 'User', same, 'Account', 'OWNS']])

    account, transaction = ident('a'), ident('t')
    wash_rows = valid_chain() + [
        [account, 'Account', transaction, 'Transaction', 'SENDS'],
        [transaction, 'Transaction', account, 'Account', 'RECEIVES'],
    ]
    random.SystemRandom().shuffle(wash_rows)
    cases.append(wash_rows)

    cases.append([[ident('u'), 'User', ident('a'), 'Account']])
    cases.append([[ident('u'), 'User', ident('a'), 'Account', 'OWNS', 'EXTRA']])

    mixed = valid_chain()
    mixed.insert(1, [ident('t'), 'Transaction', ident('a'), 'Account', 'SENDS'])
    cases.append(mixed)

    account, transaction, other = ident('a'), ident('t'), ident('a')
    cases.append([
        [transaction, 'Transaction', other, 'Account', 'RECEIVES'],
        [account, 'Account', transaction, 'Transaction', 'SENDS'],
    ])

    expected = [expected_result(rows) for rows in cases]
    assert 'ACCEPT' in expected and 'REJECT' in expected

    paired = list(zip(cases, expected))
    random.SystemRandom().shuffle(paired)

    failures = []
    with tempfile.TemporaryDirectory(prefix='validator_inputs_') as case_dir:
        for rows, wanted in paired:
            filename = secrets.token_hex(16) + '.csv'
            path = os.path.join(case_dir, filename)
            with open(path, 'w', newline='') as handle:
                csv.writer(handle).writerows(rows)

            output, retcode = run_validator(path)
            if output != wanted or retcode != 0:
                failures.append((filename, wanted, output, retcode))

    if failures:
        details = "; ".join(
            f"{name} (expected: {wanted}, out: {output}, code: {code})"
            for name, wanted, output, code in failures
        )
        pytest.fail(f"Generated validation cases failed: {details}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
