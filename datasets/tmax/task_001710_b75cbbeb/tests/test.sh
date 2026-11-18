#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import secrets
import subprocess

import pytest

SCRIPT = "/home/user/clean_pipeline.py"
RAW = "/home/user/raw_data.csv"
CLEAN = "/home/user/clean_data.csv"
LOG = "/home/user/pipeline.log"
HEADERS = ['id', 'timestamp', 'user_name', 'email', 'score', 'retry_run_id', 'email_domain']


def read_csv(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def expected_from(raw_rows):
    seen = set()
    rows = []
    for raw in raw_rows:
        digest = hashlib.md5(
            (str(raw['id']) + raw['user_name'] + raw['email']).encode('utf-8')
        ).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        row = dict(raw)
        row['user_name'] = row['user_name'].encode('latin-1').decode('utf-8')
        row['score'] = None if row['score'].strip() == '' else float(row['score'])
        row['email_domain'] = row['email'].split('@', 1)[1]
        rows.append(row)

    rows.sort(key=lambda row: int(row['id']))
    missing = sum(row['score'] is None for row in rows)
    for i, row in enumerate(rows):
        if row['score'] is not None:
            continue
        left = next((j for j in range(i - 1, -1, -1) if rows[j]['score'] is not None), None)
        right = next((j for j in range(i + 1, len(rows)) if rows[j]['score'] is not None), None)
        assert left is not None and right is not None, "Verifier fixture requires internal interpolation"
        fraction = (i - left) / (right - left)
        row['score'] = rows[left]['score'] + fraction * (rows[right]['score'] - rows[left]['score'])

    log_lines = [
        f"[INFO] Initial records: {len(raw_rows)}",
        f"[INFO] Duplicates removed: {len(raw_rows) - len(rows)}",
        f"[INFO] Missing scores interpolated: {missing}",
        f"[INFO] Final records: {len(rows)}",
    ]
    return rows, log_lines


def run_pipeline():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is missing or is not a regular file."
    for path in (CLEAN, LOG):
        if os.path.lexists(path):
            os.unlink(path)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_complete_output(raw_rows):
    expected_rows, expected_log = expected_from(raw_rows)

    assert os.path.isfile(LOG), f"{LOG} is missing."
    with open(LOG, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert lines == expected_log, f"Log file contents do not match expected. Got: {lines}"

    assert os.path.isfile(CLEAN), f"{CLEAN} is missing."
    with open(CLEAN, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)
        assert reader.fieldnames == HEADERS, f"Unexpected CSV headers: {reader.fieldnames}"

    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} data rows, got {len(actual_rows)}"
    )
    for position, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert set(actual) == set(HEADERS), f"Unexpected columns in row {position}: {actual}"
        for field in HEADERS:
            if field == 'score':
                assert actual[field].strip() != '', f"Blank score in row {position}"
                assert float(actual[field]) == pytest.approx(expected[field]), (
                    f"Incorrect score in row {position}: {actual[field]}"
                )
            else:
                assert actual[field] == str(expected[field]), (
                    f"Incorrect {field} in row {position}: expected {expected[field]!r}, "
                    f"got {actual[field]!r}"
                )


@pytest.fixture(scope="module", autouse=True)
def execute_original_pipeline():
    original_rows = read_csv(RAW)
    run_pipeline()
    yield original_rows


def test_pipeline_log_exists():
    assert os.path.isfile(LOG), f"{LOG} is missing."


def test_pipeline_log_content():
    expected_log = [
        "[INFO] Initial records: 6",
        "[INFO] Duplicates removed: 2",
        "[INFO] Missing scores interpolated: 1",
        "[INFO] Final records: 4"
    ]
    with open(LOG, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert lines == expected_log, f"Log file contents do not match expected. Got: {lines}"


def test_clean_data_exists():
    assert os.path.isfile(CLEAN), f"{CLEAN} is missing."


def test_clean_data_content(execute_original_pipeline):
    raw_rows = execute_original_pipeline
    assert_complete_output(raw_rows)

    rows = read_csv(CLEAN)
    assert len(rows) == 4
    assert rows[0]['id'] == '1'
    assert rows[0]['user_name'] == 'René'
    assert float(rows[0]['score']) == 85.0
    assert rows[0]['email_domain'] == 'example.com'
    assert rows[1]['id'] == '2'
    assert rows[1]['user_name'] == 'José'
    assert float(rows[1]['score']) == 90.0
    assert rows[1]['email_domain'] == 'test.org'
    assert rows[2]['id'] == '3'
    assert rows[2]['user_name'] == 'Alice'
    assert float(rows[2]['score']) == 95.0
    assert rows[2]['email_domain'] == 'domain.com'
    assert rows[3]['id'] == '4'
    assert rows[3]['user_name'] == 'Bob'
    assert float(rows[3]['score']) == 100.0
    assert rows[3]['email_domain'] == 'test.org'


def test_pipeline_on_unseen_input():
    token = secrets.token_hex(8)
    fieldnames = ['id', 'timestamp', 'user_name', 'email', 'score', 'retry_run_id']
    rows = [
        ['60', '2024-05-01 12:00', 'RenÃ©', f'rene-{token}@alpha.example', '61.0', 'retry-a'],
        ['10', '2024-05-01 12:01', 'JosÃ©', f'jose-{token}@beta.example', '11.0', 'retry-a'],
        ['30', '2024-05-01 12:02', 'ZoÃ«', f'zoe-{token}@gamma.example', '', 'retry-a'],
        ['10', '2099-12-31 23:59', 'JosÃ©', f'jose-{token}@beta.example', '999.0', 'retry-duplicate'],
        ['20', '2024-05-01 12:04', 'MÃ¼ller', f'muller-{token}@delta.example', '21.0', 'retry-b'],
        ['50', '2024-05-01 12:05', 'FranÃ§ois', f'francois-{token}@epsilon.example', '', 'retry-b'],
        ['40', '2024-05-01 12:06', 'Alice', f'alice-{token}@zeta.example', '41.0', 'retry-c'],
    ]

    with open(RAW, 'rb') as f:
        original_raw = f.read()
    try:
        with open(RAW, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(fieldnames)
            writer.writerows(rows)
        dynamic_raw = read_csv(RAW)
        run_pipeline()
        assert_complete_output(dynamic_raw)
    finally:
        with open(RAW, 'wb') as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
