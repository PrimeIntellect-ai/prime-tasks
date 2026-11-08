#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import codecs
import csv
import json
import os
import secrets
import stat
import string
import subprocess
from collections import Counter
from pathlib import Path

import pytest

INCOMING = Path('/home/user/incoming')
PROCESSED = Path('/home/user/processed')
PIPELINE = Path('/home/user/pipeline')
PROCESS_PY = PIPELINE / 'process.py'
RUN_SH = PIPELINE / 'run.sh'
JSON_PATH = PIPELINE / 'word_frequencies.json'


def run_as_user(command):
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', *command],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


def normalize_counts(feedback_values):
    counts = Counter()
    table = str.maketrans('', '', string.punctuation)
    for raw_text in feedback_values:
        decoded = codecs.decode(raw_text.encode('ascii'), 'unicode_escape')
        normalized = decoded.lower().translate(table)
        counts.update(normalized.split())
    return counts


def write_csv(path, feedback_values):
    with path.open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=['id', 'feedback'])
        writer.writeheader()
        for index, feedback in enumerate(feedback_values, 1):
            writer.writerow({'id': index, 'feedback': feedback})
    os.chmod(path, 0o644)


def load_counts():
    with JSON_PATH.open('r', encoding='utf-8') as handle:
        return json.load(handle)


def test_directories_exist():
    directories = [
        '/home/user/incoming',
        '/home/user/processed',
        '/home/user/pipeline',
    ]
    for directory in directories:
        assert os.path.isdir(directory), f'Directory {directory} does not exist.'


def test_scripts_exist_and_executable():
    assert os.path.isfile(PROCESS_PY), f'Python script {PROCESS_PY} does not exist.'
    assert os.path.isfile(RUN_SH), f'Wrapper script {RUN_SH} does not exist.'

    st = os.stat(RUN_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f'Wrapper script {RUN_SH} is not executable.'


def test_cron_job_configured():
    try:
        result = subprocess.run(
            ['crontab', '-u', 'user', '-l'],
            capture_output=True,
            text=True,
            check=True,
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab for user 'user'.")

    expected_cron = '*/10 * * * * /home/user/pipeline/run.sh'
    lines = [
        line.strip()
        for line in crontab_content.splitlines()
        if line.strip() and not line.startswith('#')
    ]
    match_found = any(expected_cron in line for line in lines)
    assert match_found, f"Expected cron job '{expected_cron}' not found in user's crontab."


def test_incoming_directory_empty():
    assert os.path.isdir(INCOMING), f'Directory {INCOMING} does not exist.'
    files = os.listdir(INCOMING)
    assert len(files) == 0, f'Expected {INCOMING} to be empty, but found: {files}'


def test_processed_files_moved():
    assert os.path.isdir(PROCESSED), f'Directory {PROCESSED} does not exist.'
    files = set(os.listdir(PROCESSED))
    expected_files = {'batch1.csv', 'batch2.csv'}
    assert expected_files.issubset(files), (
        f'Expected files {expected_files} to be in {PROCESSED}, but found {files}'
    )


def test_word_frequencies_json():
    assert os.path.isfile(JSON_PATH), f'JSON file {JSON_PATH} does not exist.'
    try:
        data = load_counts()
    except json.JSONDecodeError:
        pytest.fail(f'File {JSON_PATH} does not contain valid JSON.')

    expected_counts = {
        'the': 2,
        'battery': 1,
        'life': 1,
        'is': 1,
        'terrible': 2,
        'love': 2,
        'screen': 2,
        'very': 1,
        'bright': 2,
        'will': 1,
        'return': 1,
        'it': 1,
    }
    assert data == expected_counts, f'Word frequencies do not match expected values. Got: {data}'


def test_pipeline_behavior_on_unseen_inputs_and_wrapper_execution():
    baseline = load_counts()
    assert isinstance(baseline, dict)
    assert all(isinstance(k, str) and isinstance(v, int) for k, v in baseline.items())

    suffix = secrets.token_hex(8)
    a = 'alpha' + suffix
    b = 'beta' + suffix
    c = 'gamma' + suffix
    d = 'delta' + suffix
    e = 'epsilon' + suffix
    sentinel = 'persist' + suffix
    seed_count = secrets.randbelow(50) + 7

    assert not ({a, b, c, d, e, sentinel} & set(baseline))
    expected = Counter(baseline)
    expected[sentinel] = seed_count
    with JSON_PATH.open('w', encoding='utf-8') as handle:
        json.dump(dict(expected), handle)

    non_csv = INCOMING / ('leave_me_' + suffix + '.txt')
    non_csv.write_text('not a csv', encoding='utf-8')
    os.chmod(non_csv, 0o644)

    first_name = 'dynamic_direct_' + suffix + '.csv'
    first_path = INCOMING / first_name
    first_feedback = [
        f'{a.upper()}\\u0021 {b}, {a}.',
        f'{b.upper()}-{c}\\u003f {c}\'s',
    ]
    write_csv(first_path, first_feedback)
    expected.update(normalize_counts(first_feedback))

    # Execute process.py itself so the implementation cannot be hidden in run.sh.
    run_as_user(['python3', str(PROCESS_PY)])
    assert not first_path.exists(), 'process.py did not remove the processed CSV from incoming.'
    assert (PROCESSED / first_name).is_file(), 'process.py did not move the CSV to processed.'
    assert non_csv.is_file(), 'process.py moved a non-CSV file.'
    assert load_counts() == dict(expected), 'process.py failed decoding, normalization, aggregation, or persistence.'

    second_name = 'dynamic_wrapper_' + suffix + '.csv'
    second_path = INCOMING / second_name
    punctuation_without_backslash = string.punctuation.replace('\\', '')
    second_feedback = [
        f'{d.upper()}{punctuation_without_backslash}{e.upper()} {d}\\u005c{e}',
        f'{e}\\u002e\\u002e {d.upper()}\\u0021',
    ]
    write_csv(second_path, second_feedback)
    expected.update(normalize_counts(second_feedback))

    # Exercise the submitted wrapper under the same account used by cron.
    run_as_user([str(RUN_SH)])
    assert not second_path.exists(), 'run.sh did not process the unseen CSV.'
    assert (PROCESSED / second_name).is_file(), 'run.sh did not move the unseen CSV.'
    assert non_csv.is_file(), 'run.sh moved a non-CSV file.'
    assert load_counts() == dict(expected), 'run.sh did not preserve and update the aggregate counts.'

    # Verify that run.sh really invokes the required process.py path.
    backup = PIPELINE / ('.process_backup_' + suffix)
    marker = PIPELINE / ('.wrapper_probe_' + suffix)
    os.replace(PROCESS_PY, backup)
    try:
        PROCESS_PY.write_text(
            '#!/usr/bin/env python3\n'
            'from pathlib import Path\n'
            f'Path({str(marker)!r}).write_text("invoked", encoding="utf-8")\n',
            encoding='utf-8',
        )
        os.chmod(PROCESS_PY, 0o755)
        run_as_user([str(RUN_SH)])
        assert marker.is_file(), 'run.sh does not execute /home/user/pipeline/process.py.'
    finally:
        if PROCESS_PY.exists():
            PROCESS_PY.unlink()
        os.replace(backup, PROCESS_PY)
        if marker.exists():
            marker.unlink()
        if non_csv.exists():
            non_csv.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
