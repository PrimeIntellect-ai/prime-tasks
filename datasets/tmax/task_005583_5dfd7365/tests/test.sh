#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess

import pytest

HOME = "/home/user"
RAW = os.path.join(HOME, "raw_sensor_data.txt")
SORTED = os.path.join(HOME, "sorted_data.csv")
ANOMALIES = os.path.join(HOME, "anomalies.csv")
DB = os.path.join(HOME, "sensor_db.sqlite")
PROCESSOR = os.path.join(HOME, "processor")
MAKEFILE = os.path.join(HOME, "Makefile")


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def expected_for_raw(path):
    rows = []
    with open(path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            sensor_id, timestamp, value = line.split()
            rows.append((int(sensor_id), int(timestamp), float(value)))

    rows.sort(key=lambda row: (row[0], row[1]))
    sorted_lines = [f"{sid},{ts},{value:.2f}" for sid, ts, value in rows]

    anomaly_rows = []
    previous = {}
    for sid, ts, value in rows:
        if sid in previous and abs(value - previous[sid]) > 20.5:
            anomaly_rows.append((sid, ts, value, previous[sid]))
        previous[sid] = value

    anomaly_lines = [
        f"{sid},{ts},{value:.2f},{prev:.2f}"
        for sid, ts, value, prev in anomaly_rows
    ]
    return rows, anomaly_rows, sorted_lines, anomaly_lines


def assert_csv_outputs(path=RAW):
    _, _, expected_sorted, expected_anomalies = expected_for_raw(path)
    assert read_nonempty_lines(SORTED) == expected_sorted
    assert read_nonempty_lines(ANOMALIES) == expected_anomalies


def assert_database(path=RAW):
    expected_rows, expected_anomalies, _, _ = expected_for_raw(path)
    assert os.path.isfile(DB), "SQLite database not found"

    conn = sqlite3.connect(DB)
    try:
        sensor_schema = conn.execute("PRAGMA table_info(sensor_data)").fetchall()
        anomaly_schema = conn.execute("PRAGMA table_info(anomalies)").fetchall()
        assert [(r[1], r[2].upper()) for r in sensor_schema] == [
            ("sensor_id", "INTEGER"),
            ("timestamp", "INTEGER"),
            ("value", "REAL"),
        ]
        assert [(r[1], r[2].upper()) for r in anomaly_schema] == [
            ("sensor_id", "INTEGER"),
            ("timestamp", "INTEGER"),
            ("value", "REAL"),
            ("prev_value", "REAL"),
        ]

        actual_rows = conn.execute(
            "SELECT sensor_id, timestamp, value FROM sensor_data "
            "ORDER BY sensor_id, timestamp"
        ).fetchall()
        actual_anomalies = conn.execute(
            "SELECT sensor_id, timestamp, value, prev_value FROM anomalies "
            "ORDER BY sensor_id, timestamp"
        ).fetchall()

        assert [(sid, ts, f"{value:.2f}") for sid, ts, value in actual_rows] == [
            (sid, ts, f"{value:.2f}") for sid, ts, value in expected_rows
        ]
        assert [
            (sid, ts, f"{value:.2f}", f"{prev:.2f}")
            for sid, ts, value, prev in actual_anomalies
        ] == [
            (sid, ts, f"{value:.2f}", f"{prev:.2f}")
            for sid, ts, value, prev in expected_anomalies
        ]
    finally:
        conn.close()


def prerequisites(makefile, target):
    result = []
    pattern = re.compile(rf"^{re.escape(target)}\s*:(.*)$", re.MULTILINE)
    for match in pattern.finditer(makefile):
        deps = match.group(1).split("#", 1)[0].split("|", 1)[0]
        result.extend(deps.split())
    return result


def run_make(*args):
    result = subprocess.run(
        ["make", *args],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout
    return result.stdout


def test_complete_pipeline():
    # Preserve the original final-state assertions for the supplied fixture.
    expected_files = [
        os.path.join(HOME, "process.c"),
        MAKEFILE,
        PROCESSOR,
        SORTED,
        ANOMALIES,
        DB,
    ]
    for file_path in expected_files:
        assert os.path.isfile(file_path), f"Missing expected file: {file_path}"

    assert read_nonempty_lines(SORTED) == [
        "1,100,12.00",
        "1,105,10.00",
        "1,110,35.00",
        "2,100,45.00",
        "2,101,46.00",
        "2,102,80.00",
        "3,500,10.00",
        "3,501,15.00",
    ]
    assert read_nonempty_lines(ANOMALIES) == [
        "1,110,35.00,10.00",
        "2,102,80.00,46.00",
    ]

    conn = sqlite3.connect(DB)
    try:
        assert conn.execute("SELECT COUNT(*) FROM sensor_data").fetchone()[0] == 8
        assert conn.execute("SELECT COUNT(*) FROM anomalies").fetchone()[0] == 2
        assert conn.execute(
            "SELECT sensor_id, timestamp FROM anomalies ORDER BY sensor_id"
        ).fetchall() == [(1, 110), (2, 102)]
    finally:
        conn.close()

    with open(MAKEFILE, "r") as f:
        makefile = f.read()
    for target in ["build", "process", "load", "all"]:
        assert f"{target}:" in makefile, f"Makefile is missing target: {target}"

    # Verify the required dependency DAG and bulk-import mechanism.
    assert "build" in prerequisites(makefile, "process")
    assert "process" in prerequisites(makefile, "load")
    assert "load" in prerequisites(makefile, "all")
    active_text = "\n".join(
        line for line in makefile.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bsqlite3\b", active_text), "load must use the sqlite3 CLI"
    assert ".import" in active_text, "load must use sqlite3 bulk import"

    # Replace the fixture with unseen data, including positive and negative
    # changepoints and an exact 20.5 difference, which is not anomalous.
    with open(RAW, "w") as f:
        f.write(
            "9 300 0.0\n"
            "1 20 31.0\n"
            "4 42 7.125\n"
            "2 7 -25.6\n"
            "9 100 100.0\n"
            "1 10 10.0\n"
            "9 200 79.49\n"
            "2 5 0.0\n"
            "1 30 51.5\n"
        )

    # Build and execute the submitted C artifact directly.
    for path in [PROCESSOR, SORTED, ANOMALIES, DB]:
        if os.path.exists(path):
            os.remove(path)
    run_make("-B", "build")
    assert os.path.isfile(PROCESSOR) and os.access(PROCESSOR, os.X_OK)
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor must be a compiled executable"
    result = subprocess.run(
        [PROCESSOR], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert result.returncode == 0, result.stdout
    assert_csv_outputs()

    # Remove every generated artifact and force the complete Makefile DAG.
    for path in [PROCESSOR, SORTED, ANOMALIES, DB]:
        if os.path.exists(path):
            os.remove(path)
    run_make("-B", "all")
    assert os.path.isfile(PROCESSOR) and os.access(PROCESSOR, os.X_OK)
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF"
    assert_csv_outputs()
    assert_database()


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
