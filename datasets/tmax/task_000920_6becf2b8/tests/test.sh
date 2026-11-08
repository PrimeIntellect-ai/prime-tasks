#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import pwd
import sqlite3
import subprocess
import tempfile
import time

import pytest
import requests

DB_PATH = "/home/user/telemetry.db"
SCRIPT_PATH = "/home/user/export_db.sh"
BACKUP_PATH = "/home/user/backup.sql"
SOURCE_PATH = "/home/user/sensor_data.csv"
URL = "http://127.0.0.1:8000/data"
TOKEN = "crimson sky"
MULTIPLIER = 2.0

EXPECTED_DATA = {
    1: {"calibrated_reading": 20.0, "rolling_avg": 20.0},
    2: {"calibrated_reading": 40.0, "rolling_avg": 30.0},
    3: {"calibrated_reading": 60.0, "rolling_avg": 40.0},
    4: {"calibrated_reading": 80.0, "rolling_avg": 60.0},
    5: {"calibrated_reading": 100.0, "rolling_avg": 80.0},
    6: {"calibrated_reading": 120.0, "rolling_avg": 100.0},
}


def derive_expected():
    with open(SOURCE_PATH, newline="") as f:
        source = sorted(
            [(int(r["timestamp"]), None if r["reading"].strip() == "" else float(r["reading"]))
             for r in csv.DictReader(f)],
            key=lambda x: x[0],
        )

    values = []
    for i, (ts, reading) in enumerate(source):
        if reading is None:
            left = next(((lts, lv) for lts, lv in reversed(source[:i]) if lv is not None), None)
            right = next(((rts, rv) for rts, rv in source[i + 1:] if rv is not None), None)
            assert left is not None and right is not None, "Test input has an unsupported edge missing value"
            reading = left[1] + (right[1] - left[1]) * (ts - left[0]) / (right[0] - left[0])
        values.append((ts, reading * MULTIPLIER))

    expected = {}
    calibrated = []
    for ts, value in values:
        calibrated.append(value)
        window = calibrated[-3:]
        expected[ts] = {
            "calibrated_reading": value,
            "rolling_avg": sum(window) / len(window),
        }
    return expected


def assert_rows_are_expected(rows, expected):
    assert len(rows) >= 6, "Not enough rows in the processed_data table."

    # Preserve the original per-row value assertions.
    for row in rows:
        ts = int(row[0])
        if ts in EXPECTED_DATA:
            fixed = EXPECTED_DATA[ts]
            assert abs(row[1] - fixed["calibrated_reading"]) < 1e-5, f"Incorrect calibrated_reading for timestamp {ts}"
            assert abs(row[2] - fixed["rolling_avg"]) < 1e-5, f"Incorrect rolling_avg for timestamp {ts}"

    # Require exactly one correctly processed row for every source timestamp.
    assert len(rows) == len(expected), "processed_data must contain exactly the source data rows"
    assert [int(row[0]) for row in rows] == sorted(expected), "processed_data timestamps do not match the source CSV"
    for ts_raw, calibrated, rolling in rows:
        ts = int(ts_raw)
        assert isinstance(calibrated, (int, float)) and not isinstance(calibrated, bool) and math.isfinite(calibrated)
        assert isinstance(rolling, (int, float)) and not isinstance(rolling, bool) and math.isfinite(rolling)
        assert abs(calibrated - expected[ts]["calibrated_reading"]) < 1e-5, f"Incorrect calibrated_reading for timestamp {ts}"
        assert abs(rolling - expected[ts]["rolling_avg"]) < 1e-5, f"Incorrect rolling_avg for timestamp {ts}"


def read_processed_rows(path):
    conn = sqlite3.connect(path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='processed_data'")
        assert cursor.fetchone() is not None, "Table 'processed_data' does not exist in the database."
        cursor.execute("SELECT timestamp, calibrated_reading, rolling_avg FROM processed_data ORDER BY timestamp")
        return cursor.fetchall()
    finally:
        conn.close()


def test_database_exists_and_has_data():
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"
    expected = derive_expected()
    assert expected == EXPECTED_DATA
    assert_rows_are_expected(read_processed_rows(DB_PATH), expected)


def test_web_service_auth_and_data():
    try:
        response = requests.get(f"{URL}?timestamp=3", timeout=2)
        assert response.status_code in [401, 403], f"Expected 401/403 without auth, got {response.status_code}"
    except requests.exceptions.ConnectionError:
        pytest.fail("Web service is not running or not reachable on 127.0.0.1:8000")

    headers = {"Authorization": "Bearer wrong token"}
    response = requests.get(f"{URL}?timestamp=3", headers=headers, timeout=2)
    assert response.status_code in [401, 403], f"Expected 401/403 with wrong auth, got {response.status_code}"

    expected = derive_expected()
    headers = {"Authorization": f"Bearer {TOKEN}"}
    for ts in sorted(expected):
        response = requests.get(f"{URL}?timestamp={ts}", headers=headers, timeout=2)
        assert response.status_code == 200, f"Expected 200 OK for timestamp {ts}, got {response.status_code}"
        try:
            data = response.json()
        except (ValueError, json.JSONDecodeError):
            pytest.fail(f"Response for timestamp {ts} is not valid JSON")
        assert set(data) == {"timestamp", "calibrated_reading", "rolling_avg"}, f"Incorrect JSON fields for timestamp {ts}"
        assert data["timestamp"] == ts, f"Incorrect timestamp in response for {ts}"
        assert isinstance(data["calibrated_reading"], (int, float)) and not isinstance(data["calibrated_reading"], bool)
        assert isinstance(data["rolling_avg"], (int, float)) and not isinstance(data["rolling_avg"], bool)
        assert math.isfinite(data["calibrated_reading"]) and math.isfinite(data["rolling_avg"])
        assert abs(data["calibrated_reading"] - expected[ts]["calibrated_reading"]) < 1e-5, f"Incorrect calibrated_reading in response for {ts}"
        assert abs(data["rolling_avg"] - expected[ts]["rolling_avg"]) < 1e-5, f"Incorrect rolling_avg in response for {ts}"


def test_cron_script_exists_and_creates_valid_dump():
    assert os.path.exists(SCRIPT_PATH), f"Export script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK) or os.access(SCRIPT_PATH, os.R_OK), "Export script should be readable/executable"
    assert os.path.isfile(SCRIPT_PATH), "Export script must be a regular file"

    if os.path.lexists(BACKUP_PATH):
        os.remove(BACKUP_PATH)

    account = pwd.getpwnam("user")
    def become_user():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    started = time.time()
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=10,
        preexec_fn=become_user,
    )
    assert result.returncode == 0, f"Export script failed: {result.stderr}"
    assert os.path.isfile(BACKUP_PATH), "Export script did not create /home/user/backup.sql"
    assert os.path.getsize(BACKUP_PATH) > 0, "Export script created an empty dump"
    assert os.path.getmtime(BACKUP_PATH) >= started - 1, "Export script did not create a fresh dump"

    with open(BACKUP_PATH, "r", encoding="utf-8") as f:
        dump_sql = f.read()
    fd, restored_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    try:
        conn = sqlite3.connect(restored_path)
        try:
            conn.executescript(dump_sql)
        finally:
            conn.close()
        assert_rows_are_expected(read_processed_rows(restored_path), derive_expected())
    finally:
        os.remove(restored_path)


def test_crontab_configured():
    try:
        result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        try:
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
            crontab_content = result.stdout
        except subprocess.CalledProcessError:
            pytest.fail("Failed to read crontab")

    valid_patterns = ["*/15", "0,15,30,45", "00,15,30,45"]
    found = False
    for line in crontab_content.splitlines():
        if SCRIPT_PATH in line and not line.strip().startswith("#"):
            parts = line.split()
            if len(parts) >= 5 and any(p in parts[0] for p in valid_patterns):
                found = True
                break
    assert found, "Crontab is not configured to run the script every 15 minutes."

    robust_found = False
    for raw_line in crontab_content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6 and parts[0] in valid_patterns and parts[1:5] == ["*", "*", "*", "*"] and SCRIPT_PATH in parts[5:]:
            robust_found = True
            break
    assert robust_found, "Crontab entry must run the export script every 15 minutes"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
