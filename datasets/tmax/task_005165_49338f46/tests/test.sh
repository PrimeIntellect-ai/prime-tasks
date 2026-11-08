#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess
from decimal import Decimal

SCRIPT_PATH = "/home/user/pipeline.sh"
RAW_PATH = "/home/user/raw.dat"
CSV_PATH = "/home/user/filtered.csv"
DB_PATH = "/home/user/sensors.db"


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_filtered_csv_content():
    assert os.path.isfile(CSV_PATH), f"Filtered CSV {CSV_PATH} does not exist."

    expected_lines = [
        "162060,S2,45.0",
        "162180,S1,55.1",
        "162300,S3,33.3"
    ]

    with open(CSV_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, f"Content of {CSV_PATH} is incorrect. Expected {expected_lines}, got {lines}."


def test_sqlite_db_content():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='valid_readings';")
    assert cursor.fetchone() is not None, "Table 'valid_readings' does not exist in the database."

    cursor.execute("SELECT timestamp, sensor_id, reading FROM valid_readings ORDER BY timestamp ASC;")
    rows = cursor.fetchall()

    expected_rows = [
        (162060, 'S2', 45.0),
        (162180, 'S1', 55.1),
        (162300, 'S3', 33.3)
    ]

    assert rows == expected_rows, f"Database content is incorrect. Expected {expected_rows}, got {rows}."
    conn.close()


def test_cron_job_configured():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        crontab_content = ""

    lines = crontab_content.strip().split('\n')
    found = False
    for line in lines:
        if line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "0 * * * *" and "/home/user/pipeline.sh" in command:
                found = True
                break

    assert found, "Cron job for /home/user/pipeline.sh to run at the top of every hour is not configured correctly."


def _remove_outputs():
    for path in (CSV_PATH, DB_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def _run_pipeline():
    return subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )


def _assert_outputs(source_rows):
    mean = sum(Decimal(reading) for _, _, reading in source_rows) / Decimal(len(source_rows))
    selected = [row for row in source_rows if Decimal(row[2]) > mean]
    expected_lines = [",".join(row) for row in selected]

    assert os.path.isfile(CSV_PATH), "Executing pipeline.sh did not create filtered.csv."
    with open(CSV_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, f"Pipeline produced incorrect CSV. Expected {expected_lines}, got {actual_lines}."

    assert os.path.isfile(DB_PATH), "Executing pipeline.sh did not create sensors.db."
    conn = sqlite3.connect(DB_PATH)
    try:
        schema = conn.execute("PRAGMA table_info(valid_readings)").fetchall()
        columns = [(row[1], row[2].upper()) for row in schema]
        assert columns == [
            ("timestamp", "INTEGER"),
            ("sensor_id", "TEXT"),
            ("reading", "REAL"),
        ], f"valid_readings has incorrect schema: {columns}"

        actual_rows = conn.execute(
            "SELECT timestamp, sensor_id, reading FROM valid_readings ORDER BY timestamp ASC"
        ).fetchall()
    finally:
        conn.close()

    expected_rows = [(int(ts), sensor, float(reading)) for ts, sensor, reading in selected]
    expected_rows.sort(key=lambda row: row[0])
    assert actual_rows == expected_rows, f"Pipeline imported incorrect rows. Expected {expected_rows}, got {actual_rows}."


def test_pipeline_executes_and_processes_changed_input():
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()

    rng = secrets.SystemRandom()
    while True:
        values = rng.sample(range(5, 150), 7)
        mean = Decimal(sum(values)) / Decimal(len(values))
        selected_count = sum(Decimal(value) > mean for value in values)
        if sum(values) % len(values) != 0 and 1 < selected_count < 6:
            break

    base_timestamp = rng.randrange(300000, 900000)
    source_rows = [
        (str(base_timestamp + index * 60), f"R{index + 1}", f"{value}.0")
        for index, value in enumerate(values)
    ]

    try:
        with open(RAW_PATH, "w") as f:
            for row in source_rows:
                f.write("|".join(row) + "\n")

        _remove_outputs()
        result = _run_pipeline()
        assert result.returncode == 0, (
            f"pipeline.sh failed on changed input with exit code {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        _assert_outputs(source_rows)
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        _remove_outputs()
        _run_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
