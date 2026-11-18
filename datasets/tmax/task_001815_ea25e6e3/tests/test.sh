#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_etl.py
import ast
import csv
import datetime as dt
import math
import numbers
import os
import random
import re
import secrets
import sqlite3
import subprocess
import sys

SCRIPT = "/home/user/etl_pipeline.py"
CSV_PATH = "/home/user/raw_sensors.csv"
DB_PATH = "/home/user/sensors.db"
REPORT_PATH = "/home/user/report.txt"
START = dt.datetime(2023, 10, 1, 10, 0, tzinfo=dt.timezone.utc)
EXPECTED_TIMESTAMPS = [
    (START + dt.timedelta(minutes=5 * i)).strftime("%Y-%m-%d %H:%M:%S")
    for i in range(13)
]


def check_script():
    assert os.path.isfile(SCRIPT), f"ETL script not found at {SCRIPT}"
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    bindings = {"pandas": set(), "jinja2": set()}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split(".")[0]
                if root in bindings:
                    bindings[root].add(alias.asname or root)
        elif isinstance(node, ast.ImportFrom) and node.module:
            root = node.module.split(".")[0]
            if root in bindings:
                for alias in node.names:
                    if alias.name != "*":
                        bindings[root].add(alias.asname or alias.name)

    loaded_names = {
        node.id for node in ast.walk(tree)
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load)
    }
    assert bindings["pandas"], "etl_pipeline.py must import pandas"
    assert bindings["jinja2"], "etl_pipeline.py must import jinja2"
    assert bindings["pandas"] & loaded_names, "The imported pandas API is never used"
    assert bindings["jinja2"] & loaded_names, "The imported jinja2 API is never used"
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "render"
        for node in ast.walk(tree)
    ), "The report must be rendered from a Jinja2 template"


def parse_time(value):
    value = value.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = dt.datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def derive_expected(csv_text):
    sums = {name: [0.0] * 13 for name in ("temp_c", "humidity_pct")}
    counts = {name: [0] * 13 for name in ("temp_c", "humidity_pct")}

    for row in csv.DictReader(csv_text.splitlines()):
        timestamp = parse_time(row["timestamp"])
        seconds = (timestamp - START).total_seconds()
        index = math.floor(seconds / 300)
        if not 0 <= index < 13:
            continue
        for name in ("temp_c", "humidity_pct"):
            if row[name].strip() != "":
                sums[name][index] += float(row[name])
                counts[name][index] += 1

    result = {}
    for name in ("temp_c", "humidity_pct"):
        values = [
            sums[name][i] / counts[name][i] if counts[name][i] else None
            for i in range(13)
        ]
        known = [i for i, value in enumerate(values) if value is not None]
        assert known, f"Test input unexpectedly has no values for {name}"
        for i, value in enumerate(values):
            if value is not None:
                continue
            before = [j for j in known if j < i]
            after = [j for j in known if j > i]
            if before and after:
                left, right = before[-1], after[0]
                fraction = (i - left) / (right - left)
                values[i] = values[left] + (values[right] - values[left]) * fraction
            elif before:
                # pandas' default linear interpolation propagates the final value.
                values[i] = values[before[-1]]
            elif after:
                values[i] = values[after[0]]
        result[name] = values
    return result


def run_script():
    for path in (DB_PATH, REPORT_PATH):
        if os.path.exists(path):
            os.remove(path)

    runner = r'''
import runpy
import sys
try:
    runpy.run_path("/home/user/etl_pipeline.py", run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        raise
assert "pandas" in sys.modules, "etl_pipeline.py did not load pandas at runtime"
assert "jinja2" in sys.modules, "etl_pipeline.py did not load jinja2 at runtime"
'''
    completed = subprocess.run(
        [sys.executable, "-c", runner],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert completed.returncode == 0, "etl_pipeline.py failed:\n" + completed.stdout


def validate_outputs(expected, original=False):
    # Preserve the original database existence, table, schema, row-count, and
    # endpoint assertions, then validate every row.
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cleaned_data'")
        assert cursor.fetchone() is not None, "Table 'cleaned_data' does not exist in the database."

        cursor.execute("PRAGMA table_info(cleaned_data)")
        columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
        assert "timestamp" in columns, "Column 'timestamp' missing."
        assert "temp_c" in columns, "Column 'temp_c' missing."
        assert "humidity_pct" in columns, "Column 'humidity_pct' missing."

        cursor.execute("SELECT timestamp, temp_c, humidity_pct FROM cleaned_data ORDER BY timestamp")
        rows = cursor.fetchall()
        assert len(rows) == 13, f"Expected exactly 13 rows (10:00 to 11:00 inclusive at 5-min intervals), got {len(rows)}"
        timestamps = [row[0] for row in rows]
        assert timestamps[0] == "2023-10-01 10:00:00", "First timestamp should be '2023-10-01 10:00:00'"
        assert timestamps[-1] == "2023-10-01 11:00:00", "Last timestamp should be '2023-10-01 11:00:00'"
        assert timestamps == EXPECTED_TIMESTAMPS, "Timestamps are not the complete 5-minute UTC sequence"

        for i, row in enumerate(rows):
            assert isinstance(row[0], str), f"Timestamp at row {i} is not stored as a string"
            assert isinstance(row[1], numbers.Real) and math.isfinite(float(row[1])), f"Invalid temp_c at {row[0]}"
            assert isinstance(row[2], numbers.Real) and math.isfinite(float(row[2])), f"Invalid humidity_pct at {row[0]}"
            assert math.isclose(float(row[1]), expected["temp_c"][i], rel_tol=0, abs_tol=1e-6), \
                f"Incorrect temp_c at {row[0]}: expected {expected['temp_c'][i]}, got {row[1]}"
            assert math.isclose(float(row[2]), expected["humidity_pct"][i], rel_tol=0, abs_tol=1e-6), \
                f"Incorrect humidity_pct at {row[0]}: expected {expected['humidity_pct'][i]}, got {row[2]}"

        if original:
            cursor.execute("SELECT temp_c, humidity_pct FROM cleaned_data WHERE timestamp='2023-10-01 10:00:00'")
            row = cursor.fetchone()
            assert row is not None
            assert abs(row[0] - 20.5) < 1e-5
            assert abs(row[1] - 41.0) < 1e-5
            cursor.execute("SELECT temp_c FROM cleaned_data WHERE timestamp='2023-10-01 10:05:00'")
            row = cursor.fetchone()
            assert row is not None
            assert abs(row[0] - 21.333) < 0.1
            cursor.execute("SELECT temp_c, humidity_pct FROM cleaned_data WHERE timestamp='2023-10-01 10:25:00'")
            row = cursor.fetchone()
            assert row is not None
            assert abs(row[0] - 25.0) < 1e-5
            assert abs(row[1] - 50.0) < 1e-5
    finally:
        conn.close()

    assert os.path.exists(REPORT_PATH), f"Report not found at {REPORT_PATH}"
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Server Room Environmental Report" in content, "Report title is missing."

    patterns = {
        "max_temp": r"Max Temperature:\s*([\d\.]+)\s*C",
        "min_temp": r"Min Temperature:\s*([\d\.]+)\s*C",
        "max_hum": r"Max Humidity:\s*([\d\.]+)\s*%",
        "min_hum": r"Min Humidity:\s*([\d\.]+)\s*%",
    }
    matches = {name: re.search(pattern, content) for name, pattern in patterns.items()}
    assert matches["max_temp"], "Max Temperature line missing or incorrectly formatted."
    assert matches["min_temp"], "Min Temperature line missing or incorrectly formatted."
    assert matches["max_hum"], "Max Humidity line missing or incorrectly formatted."
    assert matches["min_hum"], "Min Humidity line missing or incorrectly formatted."

    extrema = {
        "max_temp": round(max(expected["temp_c"]), 1),
        "min_temp": round(min(expected["temp_c"]), 1),
        "max_hum": round(max(expected["humidity_pct"]), 1),
        "min_hum": round(min(expected["humidity_pct"]), 1),
    }
    for name, wanted in extrema.items():
        assert float(matches[name].group(1)) == wanted, f"Incorrect report value for {name}"

    if original:
        assert float(matches["max_temp"].group(1)) == 25.0
        assert float(matches["min_temp"].group(1)) == 20.5
        assert float(matches["max_hum"].group(1)) == 50.0
        assert float(matches["min_hum"].group(1)) == 41.0

    body = "\n".join([
        "Server Room Environmental Report",
        "--------------------------------",
        f"Max Temperature: {extrema['max_temp']:.1f} C",
        f"Min Temperature: {extrema['min_temp']:.1f} C",
        f"Max Humidity: {extrema['max_hum']:.1f} %",
        f"Min Humidity: {extrema['min_hum']:.1f} %",
    ])
    assert content in (body, body + "\n"), "report.txt does not have exactly the required structure"


def main():
    check_script()
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        original_csv = f.read()

    try:
        original_expected = derive_expected(original_csv)
        run_script()
        validate_outputs(original_expected, original=True)

        rng = random.Random(secrets.randbits(128))
        shift = rng.randint(-40, 70) / 10.0
        hshift = rng.randint(-60, 80) / 10.0
        dynamic_csv = f'''timestamp,temp_c,humidity_pct
2023-10-01T10:01:00Z,{18.2 + shift:.1f},{35.4 + hshift:.1f}
2023-10-01T12:04:30+02:00,{22.6 + shift:.1f},{41.8 + hshift:.1f}
2023-10-01 10:11:00+00:00,,{47.3 + hshift:.1f}
2023-10-01T06:16:00-04:00,{26.1 + shift:.1f},
2023-10-01T10:26:00Z,{29.7 + shift:.1f},{54.2 + hshift:.1f}
2023-10-01T10:59:00+00:00,{21.4 + shift:.1f},{45.6 + hshift:.1f}
'''
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            f.write(dynamic_csv)
        dynamic_expected = derive_expected(dynamic_csv)
        run_script()
        validate_outputs(dynamic_expected)
    finally:
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            f.write(original_csv)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_etl.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
