#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import stat
import subprocess
from collections import Counter
from datetime import datetime, timedelta

import pytest

RAW_PATH = '/home/user/raw_logs.log'
CSV_PATH = '/home/user/summary.csv'
SCRIPT_PATH = '/home/user/run_pipeline.sh'
CRON_PATH = '/home/user/cron_schedule.txt'
START = datetime(2023, 10, 24, 10, 0)
END = datetime(2023, 10, 24, 10, 9, 59)


def run_pipeline():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."

    syntax = subprocess.run(
        ['/bin/bash', '-n', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert syntax.returncode == 0, f"run_pipeline.sh is not valid bash: {syntax.stderr}"

    if os.path.lexists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ['/bin/bash', SCRIPT_PATH],
        cwd='/home/user',
        env={**os.environ, 'HOME': '/home/user'},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.exists(CSV_PATH), f"Running {SCRIPT_PATH} did not create {CSV_PATH}."


def expected_rows(raw_bytes):
    # Ignoring invalid bytes is one of the explicitly permitted cleaning methods
    # and preserves the original verifier's expected three normalized paths.
    text = raw_bytes.decode('utf-8', errors='ignore')
    counts = Counter()
    paths = set()
    pattern = re.compile(
        r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]\s+\S+\s+\S+\s+(\S+)\s+\S+\s*$'
    )
    for line in text.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        timestamp = datetime.strptime(match.group(1), '%Y-%m-%d %H:%M:%S')
        if not (START <= timestamp <= END):
            continue
        minute = timestamp.replace(second=0)
        path = re.sub(r'\d+', '[NUM]', match.group(2).lower())
        paths.add(path)
        counts[(minute, path)] += 1

    rows = []
    for offset in range(10):
        minute = START + timedelta(minutes=offset)
        for path in sorted(paths):
            rows.append((minute.strftime('%Y-%m-%d %H:%M'), path, str(counts[(minute, path)])))
    return rows


def read_csv_rows():
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)
    return header, rows


@pytest.fixture(scope='module', autouse=True)
def execute_submitted_pipeline():
    run_pipeline()


def test_summary_csv_exists_and_format():
    assert os.path.exists(CSV_PATH), f"File {CSV_PATH} is missing."

    header, rows = read_csv_rows()
    assert header == ['time', 'path', 'count'], f"CSV header is incorrect: {header}"
    assert len(rows) == 30, f"Expected 30 rows (10 minutes * 3 paths), got {len(rows)}"
    assert all(len(row) == 3 for row in rows), "Every CSV data row must have exactly three columns."

    # Preserve the original chronological/path sorting assertions.
    for i in range(1, len(rows)):
        prev_time, prev_path = rows[i-1][0], rows[i-1][1]
        curr_time, curr_path = rows[i][0], rows[i][1]
        if prev_time == curr_time:
            assert prev_path <= curr_path, (
                f"Paths not sorted alphabetically for time {curr_time}: "
                f"{prev_path} came before {curr_path}"
            )
        else:
            assert prev_time < curr_time, (
                f"Times not sorted chronologically: {prev_time} came before {curr_time}"
            )


def test_summary_csv_data():
    assert os.path.exists(CSV_PATH), f"File {CSV_PATH} is missing."

    data = []
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)

    def get_count(time_str, path_keyword):
        matches = [int(row['count']) for row in data
                   if row['time'] == time_str and path_keyword in row['path']]
        assert len(matches) == 1, (
            f"Expected exactly 1 match for time {time_str} and path containing "
            f"{path_keyword}, got {len(matches)}"
        )
        return matches[0]

    assert get_count('2023-10-24 10:00', 'users') == 1
    assert get_count('2023-10-24 10:00', 'item') == 1
    assert get_count('2023-10-24 10:00', 'status') == 0
    assert get_count('2023-10-24 10:02', 'users') == 1
    assert get_count('2023-10-24 10:02', 'item') == 1
    assert get_count('2023-10-24 10:05', 'users') == 1
    assert get_count('2023-10-24 10:09', 'status') == 1


def test_summary_csv_all_rows_exactly_match_log():
    with open(RAW_PATH, 'rb') as f:
        expected = expected_rows(f.read())
    header, rows = read_csv_rows()
    assert header == ['time', 'path', 'count']
    actual = [tuple(row) for row in rows]
    assert actual == expected, "CSV rows do not exactly match the normalized, gap-filled log aggregation."


def test_cron_schedule():
    assert os.path.exists(CRON_PATH), f"File {CRON_PATH} is missing."

    with open(CRON_PATH, 'r', encoding='utf-8') as f:
        raw_cron = f.read()
    cron = raw_cron.strip()

    # Preserve the original checks.
    assert cron.startswith('*/5 * * * *') or cron.startswith(
        '0,5,10,15,20,25,30,35,40,45,50,55 * * * *'
    ), f"Cron schedule does not run every 5 minutes: {cron}"
    assert '/home/user/run_pipeline.sh' in cron, (
        f"Cron schedule does not contain the correct script path: {cron}"
    )

    prescribed = '*/5 * * * * /home/user/run_pipeline.sh'
    assert raw_cron in (prescribed, prescribed + '\n'), (
        f"cron_schedule.txt must contain exactly one prescribed crontab line: {prescribed!r}"
    )


def test_zz_pipeline_processes_derived_input_not_fixed_output():
    with open(RAW_PATH, 'rb') as f:
        original_raw = f.read()

    rng = random.SystemRandom()
    nonce = ''.join(rng.choice('abcdefghjkmnpqrstuvwxyz') for _ in range(10))
    lines = []
    base_paths = [
        f'/Service{nonce}/V{{id}}/Users/{{user}}/Profile',
        f'/Shop{nonce}/Item/{{id}}/Part{{part}}',
        f'/Health{nonce}/V{{id}}/Status',
    ]

    # Ensure each path appears, while varying IDs, case, minutes, seconds and counts.
    for path_index, template in enumerate(base_paths):
        chosen_minutes = {path_index, 9 - path_index, rng.randrange(10)}
        for minute in sorted(chosen_minutes):
            repetitions = rng.randint(1, 3)
            for repetition in range(repetitions):
                second = rng.randrange(60)
                rendered = template.format(
                    id=rng.randint(1, 99999),
                    user=rng.randint(1, 99999),
                    part=rng.randint(1, 99999),
                )
                if (minute + repetition + path_index) % 2:
                    rendered = rendered.upper()
                method = 'POST' if repetition % 2 else 'GET'
                lines.append(
                    f'[2023-10-24 10:{minute:02d}:{second:02d}] 10.1.{path_index}.{repetition + 1} '
                    f'{method} {rendered} 200\n'.encode('utf-8')
                )

    # Out-of-window records must not introduce either paths or counts.
    lines.extend([
        f'[2023-10-24 09:59:59] 1.1.1.1 GET /outside/{nonce}/111 200\n'.encode(),
        f'[2023-10-24 10:10:00] 1.1.1.2 GET /outside/{nonce}/222 200\n'.encode(),
    ])
    rng.shuffle(lines)
    challenge_raw = b''.join(lines)
    expected = expected_rows(challenge_raw)

    try:
        with open(RAW_PATH, 'wb') as f:
            f.write(challenge_raw)
        run_pipeline()
        header, rows = read_csv_rows()
        assert header == ['time', 'path', 'count']
        assert [tuple(row) for row in rows] == expected, (
            "Pipeline output did not match the verifier-derived aggregation for a fresh log input."
        )
    finally:
        with open(RAW_PATH, 'wb') as f:
            f.write(original_raw)

    # Restore the required final artifact for the supplied log as well.
    run_pipeline()
    header, rows = read_csv_rows()
    assert header == ['time', 'path', 'count']
    assert [tuple(row) for row in rows] == expected_rows(original_raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
