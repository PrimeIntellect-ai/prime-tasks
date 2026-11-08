#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
from collections import defaultdict

def test_rolling_loc_stats():
    input_file = "/home/user/daily_loc_stats.csv"
    output_file = "/home/user/rolling_loc_stats.csv"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.exists(input_file), f"Input file {input_file} is missing."

    # 1. Read and reshape input data
    daily_sums = defaultdict(lambda: defaultdict(int))
    languages = []

    with open(input_file, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        # Expected header: Date,Project,EN,FR,ES
        languages = header[2:]

        for row in reader:
            if not row:
                continue
            date = row[0]
            for i, lang in enumerate(languages):
                count = int(row[2 + i])
                daily_sums[lang][date] += count

    # 2. Compute rolling averages
    expected_rows = []
    for lang in languages:
        dates = sorted(daily_sums[lang].keys())
        for i, date in enumerate(dates):
            window_start = max(0, i - 2)
            window_dates = dates[window_start:i + 1]
            window_sum = sum(daily_sums[lang][d] for d in window_dates)
            rolling_avg = math.floor(window_sum / len(window_dates))
            expected_rows.append((date, lang, rolling_avg))

    # Sort expected rows by Date, then Language
    expected_rows.sort(key=lambda x: (x[0], x[1]))

    # 3. Read actual output
    actual_rows = []
    with open(output_file, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            actual_header = next(reader)
        except StopIteration:
            pytest.fail(f"Output file {output_file} is empty.")

        assert actual_header == ["Date", "Language", "RollingAvgWords"], \
            f"Header in {output_file} is incorrect. Got {actual_header}."

        for row in reader:
            if not row:
                continue
            assert len(row) == 3, f"Row {row} does not have exactly 3 columns."
            actual_rows.append((row[0], row[1], int(row[2])))

    # 4. Compare
    assert len(actual_rows) == len(expected_rows), \
        f"Output file has {len(actual_rows)} rows (excluding header), expected {len(expected_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Mismatch at row {i+2}. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
