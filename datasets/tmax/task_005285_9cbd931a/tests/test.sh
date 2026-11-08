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
import collections
import glob
import json
import os
import re
import sqlite3
import subprocess
import uuid

import pytest
import requests

DB_PATH = "/home/user/logs.db"
RAW_DIR = "/home/user/raw_logs"
PROCESS_SCRIPT = "/home/user/process_logs.py"
PIPELINE_SCRIPT = "/home/user/run_pipeline.sh"
CRON_CONFIG = "/home/user/cron_config.txt"
LOG_PATTERN = re.compile(r'^(?P<ip>[\d\.]+) \S+ \S+ \[(?P<timestamp>.*?)\] "(?P<method>\S+) (?P<endpoint>\S+) \S+" \d+ \d+')


def expected_records_from_raw_logs():
    records = []
    for path in sorted(glob.glob(os.path.join(RAW_DIR, "*.log"))):
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                match = LOG_PATTERN.match(line.rstrip("\n"))
                if match:
                    record = match.groupdict()
                    endpoint = record["endpoint"].split("?", 1)[0]
                    records.append((record["ip"], record["timestamp"], record["method"], endpoint))
    return collections.Counter(records)


def database_records():
    with sqlite3.connect(DB_PATH) as conn:
        return collections.Counter(conn.execute(
            "SELECT ip, timestamp, method, endpoint FROM access_logs"
        ).fetchall())


def clear_database():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("DELETE FROM access_logs")
        conn.commit()


def run_pipeline(timeout=15):
    result = subprocess.run(
        ["/bin/bash", PIPELINE_SCRIPT],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_pylogparser_installed_and_fixed():
    try:
        import pylogparser
    except ImportError:
        pytest.fail("pylogparser is not installed or still has an ImportError.")

    examples = [
        (
            '10.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326',
            {
                "ip": "10.0.0.1",
                "timestamp": "10/Oct/2000:13:55:36 -0700",
                "method": "GET",
                "endpoint": "/apache_pb.gif",
            },
        ),
        (
            '192.168.20.7 - - [11/Nov/2001:01:02:03 +0000] "POST /api/items?id=81 HTTP/1.1" 201 42',
            {
                "ip": "192.168.20.7",
                "timestamp": "11/Nov/2001:01:02:03 +0000",
                "method": "POST",
                "endpoint": "/api/items?id=81",
            },
        ),
    ]

    for line, expected in examples:
        try:
            result = pylogparser.parse_line(line)
        except Exception as exc:
            pytest.fail(f"pylogparser.parse_line failed: {exc}")
        assert isinstance(result, dict), "parse_line should return a dictionary"
        assert result == expected, f"Incorrect parser result: expected {expected}, got {result}"

    assert pylogparser.parse_line("not an access log line") == {}


def test_database_exists_and_schema_correct():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    with sqlite3.connect(DB_PATH) as conn:
        table = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='access_logs'"
        ).fetchone()
        assert table is not None, "Table 'access_logs' does not exist in the database."

        columns = [col[1] for col in conn.execute("PRAGMA table_info(access_logs)").fetchall()]
        expected_columns = {"ip", "timestamp", "method", "endpoint"}
        assert expected_columns.issubset(set(columns)), (
            f"Table 'access_logs' missing required columns. Found: {columns}"
        )


def test_database_matches_raw_logs_and_endpoints_are_normalized():
    expected = expected_records_from_raw_logs()
    assert expected, "No parseable records were found in the supplied raw logs."

    actual = database_records()
    assert actual, "No records found in access_logs table."
    assert actual == expected, (
        "access_logs does not exactly contain the normalized records derived from "
        f"the raw .log files. Expected {expected}, got {actual}"
    )

    for record in actual:
        assert "?" not in record[3], (
            f"Endpoint {record[3]!r} is not normalized (contains '?')."
        )


def test_pipeline_scripts_actually_ingest_all_raw_logs():
    assert os.path.isfile(PROCESS_SCRIPT), f"Missing {PROCESS_SCRIPT}"
    assert os.path.isfile(PIPELINE_SCRIPT), f"Missing {PIPELINE_SCRIPT}"
    assert os.access(PIPELINE_SCRIPT, os.X_OK), (
        "run_pipeline.sh must be executable so the installed cron entry can run it"
    )

    token = uuid.uuid4().hex
    suffix = 10 + (int(token[:4], 16) % 200)
    challenge_path = os.path.join(RAW_DIR, f"verifier_{token}.log")
    challenge_line = (
        f'203.0.113.{suffix} - - [12/Dec/2012:12:12:12 +0000] '
        f'"PATCH /verifier/{token}?nonce={token} HTTP/1.1" 202 17\n'
    )

    try:
        with open(challenge_path, "w", encoding="utf-8") as handle:
            handle.write(challenge_line)

        clear_database()
        run_pipeline()

        expected = expected_records_from_raw_logs()
        actual = database_records()
        assert actual == expected, (
            "Executing run_pipeline.sh did not populate access_logs from every raw "
            f"log line with normalized endpoints. Expected {expected}, got {actual}"
        )
        assert any(record[0] == f"203.0.113.{suffix}" and record[3] == f"/verifier/{token}"
                   for record in actual), "The dynamically added raw log was not ingested."
    finally:
        if os.path.exists(challenge_path):
            os.remove(challenge_path)
        if os.path.isfile(DB_PATH):
            try:
                clear_database()
                run_pipeline()
            except Exception:
                pass

    assert database_records() == expected_records_from_raw_logs(), (
        "The pipeline failed to restore the database from the supplied raw logs."
    )


def test_crontab_configured():
    assert os.path.isfile(CRON_CONFIG), f"Missing {CRON_CONFIG}"
    with open(CRON_CONFIG, "r", encoding="utf-8") as handle:
        config_lines = [line.strip() for line in handle if line.strip() and not line.lstrip().startswith("#")]
    assert any(
        re.match(r'^0\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_pipeline\.sh(?:\s|$)', line)
        for line in config_lines
    ), "cron_config.txt does not schedule run_pipeline.sh at the top of every hour."

    try:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        )
        crontab_output = result.stdout.strip()
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it installed?")

    assert "/home/user/run_pipeline.sh" in crontab_output, (
        "run_pipeline.sh not found in crontab."
    )
    lines = crontab_output.splitlines()
    found_schedule = any(
        re.match(r'^0\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_pipeline\.sh(?:\s|$)', line.strip())
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    )
    assert found_schedule, (
        "Crontab does not have the correct schedule (0 * * * *) for the script. "
        f"Output: {crontab_output}"
    )


def fetch_api_stats():
    url = "http://127.0.0.1:8888/api/ip-stats"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API server at {url}: {exc}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}"
    )
    content_type = response.headers.get("Content-Type", "").lower()
    assert "application/json" in content_type, (
        f"Expected application/json response, got {content_type!r}"
    )
    try:
        result = response.json()
    except ValueError:
        pytest.fail("API response is not valid JSON.")
    assert isinstance(result, dict), "API response must be a JSON dictionary."
    return result


def stats_from_database():
    with sqlite3.connect(DB_PATH) as conn:
        return {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT ip, COUNT(*) FROM access_logs GROUP BY ip"
            ).fetchall()
        }


def test_api_server_ip_stats():
    expected_stats = stats_from_database()
    assert expected_stats, "Database is empty, cannot verify API response."
    assert fetch_api_stats() == expected_stats, (
        "API stats do not match database stats."
    )

    token = uuid.uuid4().hex
    dynamic_ip = f"198.51.100.{10 + (int(token[:4], 16) % 200)}"
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute(
            "INSERT INTO access_logs (ip, timestamp, method, endpoint) VALUES (?, ?, ?, ?)",
            (dynamic_ip, "01/Jan/2030:00:00:00 +0000", "GET", f"/api/verifier/{token}"),
        )
        conn.commit()

    try:
        changed_expected = stats_from_database()
        changed_actual = fetch_api_stats()
        assert changed_actual == changed_expected, (
            "API did not query the current contents of logs.db after the database changed. "
            f"Expected {changed_expected}, got {changed_actual}"
        )
    finally:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute(
                "DELETE FROM access_logs WHERE ip = ? AND endpoint = ?",
                (dynamic_ip, f"/api/verifier/{token}"),
            )
            conn.commit()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
