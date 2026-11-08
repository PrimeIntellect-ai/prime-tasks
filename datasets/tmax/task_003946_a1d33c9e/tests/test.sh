#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
from collections import defaultdict, deque


def test_rolling_stats_csv():
    input_file = '/home/user/raw_translations.jsonl'
    output_file = '/home/user/rolling_stats.csv'

    assert os.path.exists(output_file), f"Output file {output_file} not found."

    # Derive expected data directly from the input file.
    expected_rows = []
    lang_queues = defaultdict(lambda: deque(maxlen=3))

    with open(input_file, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)

            if record.get("status") != "approved":
                continue

            chars = record.get("chars")
            if not isinstance(chars, int) or isinstance(chars, bool) or chars <= 0:
                continue

            lang = record.get("lang")
            lang_queues[lang].append(chars)
            avg = sum(lang_queues[lang]) / len(lang_queues[lang])

            # Exactly two digits after the decimal point, as required.
            expected_avg = f"{avg:.2f}"
            expected_rows.append([record.get("ts"), lang, str(chars), expected_avg])

    # Read actual data from the student's output.
    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, "Output CSV is empty."

        assert header == ["ts", "lang", "chars", "rolling_avg"], f"Header mismatch. Got {header}"
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), (
        f"Row count mismatch. Expected {len(expected_rows)}, got {len(actual_rows)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Mismatch at data row {i+1}. Expected {expected}, got {actual}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
