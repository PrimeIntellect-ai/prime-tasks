#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
from datetime import datetime
from zoneinfo import ZoneInfo

PIPELINE_DIR = "/home/user/pipeline"
EVENTS_LOG = os.path.join(PIPELINE_DIR, "events.log")
CORRECTED_DAU = os.path.join(PIPELINE_DIR, "corrected_dau.csv")

def get_expected_dau():
    """
    Computes the expected DAU counts using the America/New_York timezone.
    """
    expected = {}
    tz = ZoneInfo("America/New_York")

    with open(EVENTS_LOG, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split()
            if len(parts) != 2:
                continue

            ts_str, uid = parts
            ts = int(ts_str)

            # Convert timestamp to America/New_York time
            dt = datetime.fromtimestamp(ts, tz)
            day_str = dt.strftime("%Y-%m-%d")

            if day_str not in expected:
                expected[day_str] = set()
            expected[day_str].add(uid)

    # Convert sets to counts
    return {day: len(uids) for day, uids in expected.items()}

def test_corrected_dau_exists():
    assert os.path.exists(CORRECTED_DAU), f"The output file {CORRECTED_DAU} does not exist."
    assert os.path.isfile(CORRECTED_DAU), f"The path {CORRECTED_DAU} is not a file."

def test_corrected_dau_content():
    expected_dau = get_expected_dau()
    actual_dau = {}

    with open(CORRECTED_DAU, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)

        assert header == ["date", "dau"], f"Header is incorrect. Expected ['date', 'dau'], got {header}"

        for row_num, row in enumerate(reader, start=2):
            assert len(row) == 2, f"Row {row_num} does not have exactly 2 columns: {row}"
            date_str, dau_str = row

            try:
                dau_count = int(dau_str)
            except ValueError:
                assert False, f"DAU count on row {row_num} is not an integer: {dau_str}"

            actual_dau[date_str] = dau_count

    # Check that all expected dates are present and match
    for expected_date, expected_count in expected_dau.items():
        assert expected_date in actual_dau, f"Date {expected_date} is missing from the output."
        assert actual_dau[expected_date] == expected_count, (
            f"DAU count for {expected_date} is incorrect. "
            f"Expected {expected_count}, got {actual_dau[expected_date]}."
        )

    # Check for any unexpected dates
    for actual_date in actual_dau:
        assert actual_date in expected_dau, f"Unexpected date {actual_date} found in the output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
