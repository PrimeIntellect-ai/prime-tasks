#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import collections
import subprocess

SCRIPT = '/home/user/process_locales.sh'
INPUT = '/home/user/locales_etl_dump.csv'
OUTPUT = '/home/user/fr_FR_rolling_stats.csv'


def expected_output():
    records = {}
    with open(INPUT, 'r', encoding='utf-8', newline='') as f:
        for row in csv.reader(f):
            if len(row) != 6:
                continue
            ts_str, sid, loc, src, tr, sc = row
            ts = int(ts_str)
            if loc != 'fr-FR':
                continue
            if re.search(r'[A-Z]{3,}', tr):
                continue
            if sid not in records or records[sid]['ts'] < ts:
                records[sid] = {'ts': ts, 'sc': sc}

    sorted_recs = sorted(records.items(), key=lambda x: x[1]['ts'])
    last_score = 50.0
    window = collections.deque(maxlen=3)
    result = []
    for sid, data in sorted_recs:
        sc_val = last_score if data['sc'] == '' else float(data['sc'])
        last_score = sc_val
        window.append(sc_val)
        result.append({
            'ts': data['ts'],
            'sid': sid,
            'sc': round(sc_val, 1),
            'avg': round(sum(window) / len(window), 2),
        })
    return result


def test_script_executable():
    assert os.path.exists(SCRIPT), f'Script {SCRIPT} does not exist.'
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} is not a regular file.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'


def test_processed_output():
    # Ensure the submitted artifact, rather than a pre-created output, produces the result.
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    completed = subprocess.run(
        [SCRIPT], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert completed.returncode == 0, (
        f'Script exited with status {completed.returncode}. stderr: {completed.stderr}'
    )
    assert os.path.isfile(OUTPUT), f'Output file {OUTPUT} was not created by the script.'

    expected_rows = expected_output()
    student_rows = []
    with open(OUTPUT, 'r', encoding='utf-8', newline='') as f:
        for row in csv.reader(f):
            if not row:
                continue
            assert len(row) == 4, f'Expected 4 columns in output CSV, got {len(row)} in row: {row}'
            ts, sid, sc, ra = row
            student_rows.append({'ts': int(ts), 'sid': sid, 'sc': float(sc), 'avg': float(ra)})

    assert len(student_rows) == len(expected_rows), (
        f'Expected {len(expected_rows)} rows in the output, but got {len(student_rows)}. '
        'Check your filtering and deduplication logic.'
    )
    for i, (exp, stu) in enumerate(zip(expected_rows, student_rows)):
        assert exp['ts'] == stu['ts'], f"Row {i+1}: Expected timestamp {exp['ts']}, got {stu['ts']}. Sort order or deduplication may be incorrect."
        assert exp['sid'] == stu['sid'], f"Row {i+1}: Expected string_id {exp['sid']}, got {stu['sid']}."
        assert abs(exp['sc'] - stu['sc']) < 1e-5, (
            f"Row {i+1} (string_id {exp['sid']}): Expected confidence_score {exp['sc']}, got {stu['sc']}. Check your imputation logic."
        )
        assert abs(exp['avg'] - stu['avg']) < 1e-2 + 1e-5, (
            f"Row {i+1} (string_id {exp['sid']}): Expected rolling_avg {exp['avg']}, got {stu['avg']}. Check your rolling average calculation."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
