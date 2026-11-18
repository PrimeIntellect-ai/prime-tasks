#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import uuid
import shutil
import hashlib
import secrets
import subprocess
from collections import Counter
from pathlib import Path


def test_aggregated_csv_exists_and_correct():
    csv_path = "/home/user/loc_aggregated.csv"
    assert os.path.isfile(csv_path), f"Expected output CSV file {csv_path} does not exist."

    expected_rows = [
        ['hour', 'unique_events'],
        ['2023-10-01T10', '2'],
        ['2023-10-01T11', '2'],
        ['2023-10-02T08', '1']
    ]

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if row]

    assert actual_rows == expected_rows, f"CSV content does not match expected output. Got: {actual_rows}"


def test_pipeline_log_exists_and_correct():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"Expected log file {log_path} does not exist."

    expected_logs = [
        "PIPELINE_START",
        "TOTAL_LINES: 8",
        "DUPLICATES_REMOVED: 3",
        "PIPELINE_COMPLETE"
    ]

    with open(log_path, 'r', encoding='utf-8') as f:
        actual_logs = [line.strip() for line in f if line.strip()]

    assert actual_logs == expected_logs, f"Log content does not match expected output. Got: {actual_logs}"


def test_script_executes_pipeline_on_unseen_input():
    script = Path('/home/user/process_loc.py')
    assert script.is_file(), f"Expected pipeline script {script} does not exist."

    logs_dir = Path('/home/user/loc_logs')
    csv_path = Path('/home/user/loc_aggregated.csv')
    log_path = Path('/home/user/pipeline.log')
    backup_dir = Path('/tmp') / ('loc_logs_backup_' + uuid.uuid4().hex)

    saved_outputs = {}
    for path in (csv_path, log_path):
        saved_outputs[path] = path.read_bytes() if path.exists() else None

    year = 2040 + secrets.randbelow(20)
    month = 1 + secrets.randbelow(9)
    prefix = uuid.uuid4().hex
    hour1 = f'{year:04d}-{month:02d}-03T07'
    hour2 = f'{year:04d}-{month:02d}-03T19'
    hour3 = f'{year:04d}-{month:02d}-04T02'
    t1 = hour1 + ':11:12Z'
    t2 = hour2 + ':22:23Z'
    t3 = hour3 + ':33:34Z'

    # Each tuple contains the serialized text value and its independently known
    # cleaned value. Duplicate identity intentionally ignores user_id.
    specs = [
        (t1, prefix + '_cafe', 'Café', 'Café', 10),
        (t1, prefix + '_cafe', 'Caf\\u00e9', 'Café', 99),
        (t1, prefix + '_cafe', 'Caf\\u00e9', 'Café', 101),
        (t1, prefix + '_other', 'Café', 'Café', 10),
        (t2, prefix + '_bye', 'Adi\\u00f3s', 'Adiós', 20),
        (t2, prefix + '_bye', 'Adiós', 'Adiós', 21),
        (t3, prefix + '_city', '\\u6771\\u4eac', '東京', 30),
        (t3, prefix + '_city', '東京', '東京', 31),
        (t3, prefix + '_city', '\\u6771\\u4eac', '東京', 32),
    ]

    seen = set()
    expected_counts = Counter()
    duplicate_count = 0
    for timestamp, loc_key, _raw_text, clean_text, _user_id in specs:
        digest = hashlib.md5(
            f'{timestamp}|{loc_key}|{clean_text}'.encode('utf-8')
        ).hexdigest()
        if digest in seen:
            duplicate_count += 1
        else:
            seen.add(digest)
            expected_counts[timestamp[:13]] += 1

    expected_rows = [['hour', 'unique_events']] + [
        [hour, str(expected_counts[hour])] for hour in sorted(expected_counts)
    ]
    expected_logs = [
        'PIPELINE_START',
        f'TOTAL_LINES: {len(specs)}',
        f'DUPLICATES_REMOVED: {duplicate_count}',
        'PIPELINE_COMPLETE',
    ]

    try:
        logs_dir.rename(backup_dir)
        logs_dir.mkdir()
        split = 5
        for filename, group in (('alpha.jsonl', specs[:split]), ('beta.jsonl', specs[split:])):
            with (logs_dir / filename).open('w', encoding='utf-8') as handle:
                for timestamp, loc_key, raw_text, _clean_text, user_id in group:
                    record = {
                        'timestamp': timestamp,
                        'loc_key': loc_key,
                        'text': raw_text,
                        'user_id': user_id,
                    }
                    handle.write(json.dumps(record, ensure_ascii=False) + '\n')

        for path in (csv_path, log_path):
            if path.exists() or path.is_symlink():
                path.unlink()

        result = subprocess.run(
            ['python3', str(script)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'Pipeline exited with {result.returncode}. '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        assert csv_path.is_file(), 'Pipeline did not create loc_aggregated.csv.'
        assert log_path.is_file(), 'Pipeline did not create pipeline.log.'

        with csv_path.open('r', encoding='utf-8', newline='') as handle:
            actual_rows = [row for row in csv.reader(handle) if row]
        assert actual_rows == expected_rows, (
            f'CSV for unseen input is incorrect. Expected {expected_rows}, got {actual_rows}'
        )

        with log_path.open('r', encoding='utf-8') as handle:
            actual_logs = [line.strip() for line in handle if line.strip()]
        assert actual_logs == expected_logs, (
            f'Log for unseen input is incorrect. Expected {expected_logs}, got {actual_logs}'
        )
    finally:
        if logs_dir.exists():
            shutil.rmtree(logs_dir)
        if backup_dir.exists():
            backup_dir.rename(logs_dir)
        for path, content in saved_outputs.items():
            if content is None:
                if path.exists() or path.is_symlink():
                    path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
