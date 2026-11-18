#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta

SCRIPT = '/home/user/analyze_logs.py'
INPUT = '/home/user/system_logs.csv'
OUTPUT = '/home/user/error_trends.csv'


def get_bucket(ts):
    minute = (ts.minute // 5) * 5
    return ts.replace(minute=minute, second=0, microsecond=0)


def compute_expected(input_file):
    earliest = None
    latest = None
    counts = {}

    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = datetime.strptime(row['timestamp'], "%Y-%m-%dT%H:%M:%SZ")
            if earliest is None or ts < earliest:
                earliest = ts
            if latest is None or ts > latest:
                latest = ts
            if row['level'] == 'ERROR':
                bucket = get_bucket(ts)
                counts[bucket] = counts.get(bucket, 0) + 1

    expected_rows = []
    if earliest is not None:
        current = get_bucket(earliest)
        end_bucket = get_bucket(latest)
        history = []
        while current <= end_bucket:
            count = counts.get(current, 0)
            history.append(count)
            window = history[-3:]
            expected_rows.append({
                'bucket_start': current.strftime("%Y-%m-%dT%H:%M:%SZ"),
                'error_count': str(count),
                'sma_3': f"{sum(window) / len(window):.2f}",
            })
            current += timedelta(minutes=5)
    return expected_rows


def assert_output_matches(input_file, output_file):
    expected_rows = compute_expected(input_file)
    with open(output_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)
        expected_headers = ['bucket_start', 'error_count', 'sma_3']
        assert reader.fieldnames == expected_headers, f"Headers in output file are incorrect. Expected {expected_headers}, got {reader.fieldnames}"

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(actual_rows)}. Ensure continuous 5-minute buckets are generated."
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual['bucket_start'] == expected['bucket_start'], f"Row {i+1}: expected bucket_start {expected['bucket_start']}, got {actual['bucket_start']}"
        assert actual['error_count'] == expected['error_count'], f"Row {i+1} ({expected['bucket_start']}): expected error_count {expected['error_count']}, got {actual['error_count']}"
        assert actual['sma_3'] == expected['sma_3'], f"Row {i+1} ({expected['bucket_start']}): expected sma_3 {expected['sma_3']}, got {actual['sma_3']}"


def test_analyze_logs_script_exists_and_generates_output():
    assert os.path.exists(SCRIPT), f"The script {SCRIPT} was not created."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file."
    os.remove(OUTPUT) if os.path.exists(OUTPUT) else None
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"analyze_logs.py failed:\n{result.stderr}"
    assert os.path.isfile(OUTPUT), "analyze_logs.py did not generate /home/user/error_trends.csv."


def test_error_trends_file_exists():
    assert os.path.exists('/home/user/error_trends.csv'), "The file /home/user/error_trends.csv was not created."
    assert os.path.isfile('/home/user/error_trends.csv'), "/home/user/error_trends.csv is not a regular file."


def test_error_trends_content():
    input_file = '/home/user/system_logs.csv'
    output_file = '/home/user/error_trends.csv'

    assert os.path.exists(input_file), f"Input file {input_file} is missing, cannot verify."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    # Read input and compute expected dynamically
    earliest = None
    latest = None
    counts = {}

    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = datetime.strptime(row['timestamp'], "%Y-%m-%dT%H:%M:%SZ")
            if earliest is None or ts < earliest:
                earliest = ts
            if latest is None or ts > latest:
                latest = ts

            if row['level'] == 'ERROR':
                b = get_bucket(ts)
                counts[b] = counts.get(b, 0) + 1

    expected_rows = []
    if earliest is not None:
        start_bucket = get_bucket(earliest)
        end_bucket = get_bucket(latest)

        current = start_bucket
        buckets = []
        while current <= end_bucket:
            buckets.append(current)
            current += timedelta(minutes=5)

        history = []
        for b in buckets:
            c = counts.get(b, 0)
            history.append(c)
            window = history[-3:]
            sma = sum(window) / len(window)

            expected_rows.append({
                'bucket_start': b.strftime("%Y-%m-%dT%H:%M:%SZ"),
                'error_count': str(c),
                'sma_3': f"{sma:.2f}"
            })

    # Read actual output
    with open(output_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    expected_headers = ['bucket_start', 'error_count', 'sma_3']
    assert reader.fieldnames == expected_headers, f"Headers in output file are incorrect. Expected {expected_headers}, got {reader.fieldnames}"

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(actual_rows)}. Ensure continuous 5-minute buckets are generated."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual['bucket_start'] == expected['bucket_start'], f"Row {i+1}: expected bucket_start {expected['bucket_start']}, got {actual['bucket_start']}"
        assert actual['error_count'] == expected['error_count'], f"Row {i+1} ({expected['bucket_start']}): expected error_count {expected['error_count']}, got {actual['error_count']}"
        assert actual['sma_3'] == expected['sma_3'], f"Row {i+1} ({expected['bucket_start']}): expected sma_3 {expected['sma_3']}, got {actual['sma_3']}"


def process_tree_rss(root_pid):
    processes = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/status') as f:
                ppid = None
                rss = 0
                for line in f:
                    if line.startswith('PPid:'):
                        ppid = int(line.split()[1])
                    elif line.startswith('VmRSS:'):
                        rss = int(line.split()[1]) * 1024
                processes[int(entry)] = (ppid, rss)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _) in processes.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return sum(processes.get(pid, (None, 0))[1] for pid in descendants)


def test_script_handles_unseen_large_multiline_csv_streamingly():
    original_input = open(INPUT, 'rb').read()
    original_output = open(OUTPUT, 'rb').read() if os.path.exists(OUTPUT) else None
    try:
        base = datetime(2024, 2, 3, 8, 0, 0)
        row_count = 220000
        bucket_count = 7
        with open(INPUT, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'level', 'component', 'message'])
            for i in range(row_count):
                bucket_index = min(bucket_count - 1, (i * bucket_count) // row_count)
                ts = base + timedelta(minutes=5 * bucket_index, seconds=i % 300)
                level = 'ERROR' if (i % 11 == 0 or i % 97 == 0) else ('WARNING' if i % 13 == 0 else 'INFO')
                message = f"record {i}\ncontinued detail " + ('x' * 480)
                writer.writerow([ts.strftime('%Y-%m-%dT%H:%M:%SZ'), level, f'component-{i % 9}', message])

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)

        proc = subprocess.Popen(
            [sys.executable, SCRIPT],
            cwd='/home/user',
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        peak_rss = 0
        memory_limit = 170 * 1024 * 1024
        deadline = time.monotonic() + 90
        memory_exceeded = False
        while proc.poll() is None:
            peak_rss = max(peak_rss, process_tree_rss(proc.pid))
            if peak_rss > memory_limit:
                memory_exceeded = True
                proc.kill()
                break
            if time.monotonic() > deadline:
                proc.kill()
                raise AssertionError('analyze_logs.py timed out on the large streaming input.')
            time.sleep(0.02)

        stderr = proc.communicate()[1]
        assert not memory_exceeded, f"analyze_logs.py used {peak_rss / (1024 * 1024):.1f} MiB on the large input; process the CSV in a streaming/chunked fashion instead of loading it all into memory."
        assert proc.returncode == 0, f"analyze_logs.py failed on an unseen multiline CSV:\n{stderr}"
        assert os.path.isfile(OUTPUT), 'analyze_logs.py did not generate output for the unseen input.'
        assert_output_matches(INPUT, OUTPUT)
    finally:
        with open(INPUT, 'wb') as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
