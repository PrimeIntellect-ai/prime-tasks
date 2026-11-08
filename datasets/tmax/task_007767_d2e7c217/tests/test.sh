#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import secrets
import subprocess
from datetime import datetime, timedelta


def test_clean_metrics_exists():
    assert os.path.isfile('/home/user/clean_metrics.csv'), "The output file /home/user/clean_metrics.csv does not exist."


def test_clean_metrics_content():
    raw_file = '/home/user/raw_metrics.csv'
    assert os.path.isfile(raw_file), f"Raw metrics file {raw_file} is missing."

    # Read and parse raw data
    with open(raw_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        raw_data = list(reader)

    # Process data to derive expected output
    processed = []
    for row in raw_data:
        # Timestamp alignment
        ts = datetime.strptime(row['timestamp'], '%Y-%m-%dT%H:%M:%SZ')
        aligned = ts.strftime('%Y-%m-%d %H:%M:00')

        # CPU parsing
        cpu = float(row['cpu_percent'])

        # Memory normalization
        mem_str = row['memory_usage'].strip().upper()
        if mem_str.endswith('GB'):
            mem = float(mem_str[:-2]) * 1024
        elif mem_str.endswith('MB'):
            mem = float(mem_str[:-2])
        elif mem_str.endswith('KB'):
            mem = float(mem_str[:-2]) / 1024
        else:
            mem = float(mem_str)

        processed.append({
            'aligned_minute': aligned,
            'cpu_percent': cpu,
            'memory_mb': mem
        })

    # Sort chronologically
    processed.sort(key=lambda x: x['aligned_minute'])

    # Calculate rolling 3-row average for CPU
    for i in range(len(processed)):
        start_idx = max(0, i - 2)
        window = [x['cpu_percent'] for x in processed[start_idx:i+1]]
        processed[i]['rolling_cpu_3m'] = sum(window) / len(window)

    # Read actual output data
    out_file = '/home/user/clean_metrics.csv'
    with open(out_file, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            assert False, f"{out_file} is empty."
        out_data = list(reader)

    expected_headers = ['aligned_minute', 'cpu_percent', 'memory_mb', 'rolling_cpu_3m']
    assert headers == expected_headers, f"Header row is incorrect. Expected {expected_headers}, got {headers}."

    assert len(out_data) == len(processed), f"Number of rows in output ({len(out_data)}) does not match expected ({len(processed)})."

    for i, (out_row, exp_row) in enumerate(zip(out_data, processed)):
        assert len(out_row) == 4, f"Row {i+1} does not have exactly 4 columns."

        expected_aligned = exp_row['aligned_minute']
        expected_cpu = f"{exp_row['cpu_percent']:.2f}"
        expected_mem = f"{exp_row['memory_mb']:.2f}"
        expected_rolling = f"{exp_row['rolling_cpu_3m']:.2f}"

        assert out_row[0] == expected_aligned, f"Row {i+1}: Aligned minute mismatch. Expected {expected_aligned}, got {out_row[0]}."
        assert out_row[1] == expected_cpu, f"Row {i+1}: CPU percent mismatch or formatting error. Expected {expected_cpu}, got {out_row[1]}."
        assert out_row[2] == expected_mem, f"Row {i+1}: Memory MB mismatch or formatting error. Expected {expected_mem}, got {out_row[2]}."
        assert out_row[3] == expected_rolling, f"Row {i+1}: Rolling CPU mismatch or formatting error. Expected {expected_rolling}, got {out_row[3]}."


def test_process_metrics_script_on_dynamic_input():
    script = '/home/user/process_metrics.py'
    raw_file = '/home/user/raw_metrics.csv'
    out_file = '/home/user/clean_metrics.csv'
    assert os.path.isfile(script), "The required Python script /home/user/process_metrics.py does not exist."

    old_raw = open(raw_file, 'rb').read()
    old_output = open(out_file, 'rb').read() if os.path.isfile(out_file) else None
    rng = secrets.SystemRandom()

    base = datetime(2024 + rng.randrange(2), 1 + rng.randrange(12), 1 + rng.randrange(20), rng.randrange(0, 20), rng.randrange(0, 20))
    offsets = [0, 2, 5, 9, 14, 20, 27, 35]
    rows = []
    expected = []
    for i, offset in enumerate(offsets):
        ts = base + timedelta(minutes=offset, seconds=rng.randrange(1, 60))
        cpu = rng.randrange(10, 91)
        if i % 3 == 0:
            amount = rng.randrange(1, 5) + rng.choice([0.0, 0.25, 0.5, 0.75])
            memory_usage = f"{amount:g}GB"
            memory_mb = amount * 1024
        elif i % 3 == 1:
            amount = rng.randrange(250, 5000)
            memory_usage = f"{amount}MB"
            memory_mb = float(amount)
        else:
            amount = rng.randrange(1000, 5000000)
            memory_usage = f"{amount}KB"
            memory_mb = amount / 1024

        rows.append({
            'timestamp': ts.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'cpu_percent': str(cpu),
            'memory_usage': memory_usage,
            'incident_log': f"dynamic incident {i}\ncontinuation {rng.randrange(1000000)}" if i % 2 == 0 else f"incident {i}"
        })
        expected.append({
            'aligned_minute': ts.strftime('%Y-%m-%d %H:%M:00'),
            'cpu_percent': float(cpu),
            'memory_mb': memory_mb
        })

    rng.shuffle(rows)
    expected.sort(key=lambda row: row['aligned_minute'])
    for i, row in enumerate(expected):
        window = expected[max(0, i - 2):i + 1]
        row['rolling_cpu_3m'] = sum(item['cpu_percent'] for item in window) / len(window)

    try:
        with open(raw_file, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['timestamp', 'cpu_percent', 'memory_usage', 'incident_log'])
            writer.writeheader()
            writer.writerows(rows)
        if os.path.exists(out_file):
            os.remove(out_file)

        result = subprocess.run(
            ['python3', script], cwd='/home/user', text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert result.returncode == 0, f"process_metrics.py failed on dynamic input:\n{result.stderr}"
        assert os.path.isfile(out_file), "process_metrics.py did not generate /home/user/clean_metrics.csv."

        with open(out_file, 'r', newline='') as f:
            reader = csv.reader(f)
            actual = list(reader)

        expected_header = ['aligned_minute', 'cpu_percent', 'memory_mb', 'rolling_cpu_3m']
        assert actual, "The dynamically generated output is empty."
        assert actual[0] == expected_header, f"Dynamic output header is incorrect: {actual[0]}"
        assert len(actual[1:]) == len(expected), "Dynamic output has the wrong number of rows."

        for i, (out_row, exp_row) in enumerate(zip(actual[1:], expected), 1):
            wanted = [
                exp_row['aligned_minute'],
                f"{exp_row['cpu_percent']:.2f}",
                f"{exp_row['memory_mb']:.2f}",
                f"{exp_row['rolling_cpu_3m']:.2f}"
            ]
            assert out_row == wanted, f"Dynamic output row {i} is incorrect. Expected {wanted}, got {out_row}."
    finally:
        with open(raw_file, 'wb') as f:
            f.write(old_raw)
        if old_output is None:
            if os.path.exists(out_file):
                os.remove(out_file)
        else:
            with open(out_file, 'wb') as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
