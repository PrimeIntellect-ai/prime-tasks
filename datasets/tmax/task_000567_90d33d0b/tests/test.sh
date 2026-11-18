#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/metrics.db"
CSV_PATH = "/home/user/results.csv"
PROJECT_PATH = "/home/user/metrics_processor"
SOURCE_PATH = "/home/user/metrics_processor/src/main.rs"
EXPECTED_HEADER = ["device_name", "timestamp", "reading", "rolling_avg"]


def run_program(threshold):
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--", str(threshold)],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust utility failed for threshold {threshold}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def get_expected_data(threshold=45.0):
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Recompute the expected data based on the requirements.
    query = """
        SELECT d.name, m.timestamp, m.reading,
               AVG(m.reading) OVER (
                   PARTITION BY m.device_id
                   ORDER BY m.timestamp
                   ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
               ) as rolling_avg
        FROM measurements m
        JOIN devices d ON m.device_id = d.id
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    filtered = [r for r in rows if r[2] > threshold]
    filtered.sort(key=lambda x: (x[0], x[1]))
    return filtered[5:15]


def assert_results_csv(expected_data):
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} was not generated."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file."

    with open(CSV_PATH, mode="r", newline="") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "CSV file is empty."
    header = reader[0]
    assert header == EXPECTED_HEADER, (
        f"CSV header is incorrect. Expected {EXPECTED_HEADER}, got {header}."
    )

    actual_data = reader[1:]
    assert len(actual_data) == len(expected_data), (
        f"Expected exactly {len(expected_data)} rows of data, got {len(actual_data)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert len(actual) == 4, f"Row {i+1} does not have exactly 4 columns: {actual}"
        actual_device, actual_ts, actual_reading, actual_rolling = actual
        exp_device, exp_ts, exp_reading, exp_rolling = expected

        assert actual_device == exp_device, (
            f"Row {i+1}: expected device_name '{exp_device}', got '{actual_device}'"
        )
        assert actual_ts == exp_ts, (
            f"Row {i+1}: expected timestamp '{exp_ts}', got '{actual_ts}'"
        )

        try:
            actual_reading_float = float(actual_reading)
        except ValueError:
            pytest.fail(f"Row {i+1}: reading '{actual_reading}' is not a valid float.")

        assert abs(actual_reading_float - exp_reading) < 1e-6, (
            f"Row {i+1}: expected reading {exp_reading}, got {actual_reading_float}"
        )
        exp_rolling_str = f"{exp_rolling:.2f}"
        assert actual_rolling == exp_rolling_str, (
            f"Row {i+1}: expected rolling_avg '{exp_rolling_str}' "
            f"(formatted to 2 decimals), got '{actual_rolling}'"
        )


def inspect_rust_source():
    assert os.path.isfile(SOURCE_PATH), f"Rust source {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "Rust source file is empty."

    # Ignore comments so required SQL cannot be satisfied only by explanatory text.
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    normalized = re.sub(r"\s+", " ", code).lower()

    assert "reindex idx_measurements_ts" in normalized, (
        "main.rs must issue REINDEX idx_measurements_ts."
    )
    direct_reindex = re.search(
        r"execute(?:_batch)?\s*\([^\)]{0,800}reindex\s+idx_measurements_ts",
        code,
        flags=re.I | re.S,
    )
    assigned_reindex = re.search(
        r"(?:let|const)\s+(\w+)[^=]*=\s*r?\#*\"[^\"]*reindex\s+idx_measurements_ts[^\"]*\"",
        code,
        flags=re.I | re.S,
    )
    assigned_is_executed = False
    if assigned_reindex:
        name = re.escape(assigned_reindex.group(1))
        assigned_is_executed = bool(re.search(
            rf"execute(?:_batch)?\s*\([^\)]*\b{name}\b",
            code,
            flags=re.I | re.S,
        ))
    assert direct_reindex or assigned_is_executed, (
        "REINDEX must be executed through rusqlite, not merely mentioned."
    )

    assert re.search(r"avg\s*\([^)]*reading[^)]*\)\s*over\s*\(", normalized), (
        "The query must calculate AVG(reading) with a window function."
    )
    assert "partition by" in normalized and "order by" in normalized, (
        "The window must partition and order the measurements."
    )
    assert re.search(
        r"rows\s+between\s+2\s+preceding\s+and\s+current\s+row", normalized
    ), "The window frame must include the current row and two preceding rows."
    assert re.search(r"\bjoin\s+devices\b", normalized), (
        "The query must join the devices table."
    )
    assert re.search(r"\blimit\s+10\b", normalized), "The query must use LIMIT 10."
    assert re.search(r"\boffset\s+5\b", normalized), "The query must use OFFSET 5."

    placeholder = re.search(
        r"reading\s*>\s*(?:\?\d*|:threshold\b|@threshold\b|\$threshold\b)",
        normalized,
    )
    binding = (
        re.search(r"(?:params|named_params)!\s*\(", code)
        or re.search(r"\[\s*&?\s*threshold\s*\]", code)
        or re.search(r"&\s*\[\s*&\s*threshold\s*\]", code)
    )
    assert placeholder and binding, (
        "The reading threshold must be represented by a SQL placeholder and bound "
        "as a rusqlite parameter."
    )


def test_utility_source_and_behavior():
    inspect_rust_source()

    # Execute the demanded artifact and retain all original CSV assertions.
    run_program("45.0")
    assert_results_csv(get_expected_data(45.0))

    # Exercise the program on verifier-generated data and a non-fixed threshold.
    fd, backup_path = tempfile.mkstemp(prefix="metrics-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    seed = random.SystemRandom().randrange(1, 1_000_000)
    threshold = 1000.0 + (seed % 997) / 100.0
    device_name = f"AAA-Dynamic-{seed}"

    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        device_id = cur.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM devices").fetchone()[0]
        cur.execute("INSERT INTO devices(id, name) VALUES (?, ?)", (device_id, device_name))

        for i in range(24):
            # Every fourth row is below threshold. Those rows must still contribute
            # to later rolling averages, which catches filtering before the window.
            if i % 4 == 0:
                reading = threshold - 100.0 - ((seed + i) % 31)
            else:
                reading = threshold + 10.0 + ((seed * 13 + i * 17) % 89)
            timestamp = f"2040-02-{1 + i // 12:02d} {i % 12:02d}:17:31"
            cur.execute(
                "INSERT INTO measurements(device_id, timestamp, reading) VALUES (?, ?, ?)",
                (device_id, timestamp, reading),
            )
        conn.commit()
        conn.close()

        expected = get_expected_data(threshold)
        assert len(expected) == 10, "Verifier-generated fixture did not produce 10 rows."
        run_program(repr(threshold))
        assert_results_csv(expected)
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.unlink(backup_path)
        # Leave the required final report generated from the original database.
        run_program("45.0")
        assert_results_csv(get_expected_data(45.0))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
