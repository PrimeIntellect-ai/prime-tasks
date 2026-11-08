#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
from collections import defaultdict

def test_memory_audit_output():
    input_file = '/home/user/config_history.csv'
    output_file = '/home/user/memory_audit.csv'

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"Path {output_file} is not a regular file."

    # Recompute expected results from the input file
    assert os.path.exists(input_file), f"Input file {input_file} is missing."

    valid_memory_updates = []

    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            mem_val_str = row.get('memory_max', '').strip()
            if mem_val_str:
                try:
                    mem_val = float(mem_val_str)
                    if 256 <= mem_val <= 32768:
                        valid_memory_updates.append({
                            'server': row['server'],
                            'time': row['time'],
                            'memory_max': mem_val
                        })
                except ValueError:
                    pass

    # Sort by server, then time
    valid_memory_updates.sort(key=lambda x: (x['server'], x['time']))

    # Group by server and calculate rolling average
    server_groups = defaultdict(list)
    for update in valid_memory_updates:
        server_groups[update['server']].append(update)

    expected_rows = []
    for server, updates in sorted(server_groups.items()):
        for i, update in enumerate(updates):
            # 3-event rolling average
            start_idx = max(0, i - 2)
            window = updates[start_idx:i+1]
            avg = sum(u['memory_max'] for u in window) / len(window)

            expected_rows.append({
                'server': server,
                'time': update['time'],
                'memory_max': update['memory_max'],
                'rolling_avg_3': round(avg, 2)
            })

    # Read student's output
    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            assert False, f"Output file {output_file} is empty."

        expected_headers = ['server', 'time', 'memory_max', 'rolling_avg_3']
        assert headers == expected_headers, f"Expected headers {expected_headers}, but got {headers}."

        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows of data, but got {len(actual_rows)}. "
        "Check your filtering and long-format conversion logic."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual[0] == expected['server'], f"Row {i+1}: Expected server '{expected['server']}', got '{actual[0]}'."
        assert actual[1] == expected['time'], f"Row {i+1}: Expected time '{expected['time']}', got '{actual[1]}'."

        try:
            actual_mem = float(actual[2])
        except ValueError:
            assert False, f"Row {i+1}: Invalid memory_max value '{actual[2]}'."
        assert actual_mem == expected['memory_max'], f"Row {i+1}: Expected memory_max {expected['memory_max']}, got {actual_mem}."

        # rolling_avg_3 should be formatted to 2 decimal places
        expected_avg_str = f"{expected['rolling_avg_3']:.2f}"
        assert actual[3] == expected_avg_str, (
            f"Row {i+1}: Expected rolling_avg_3 '{expected_avg_str}', got '{actual[3]}'. "
            "Ensure it is correctly calculated and rounded to 2 decimal places."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
