#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import io
import secrets
import shutil
import sqlite3
import stat
import subprocess
import pytest

LOG_PATH = "/home/user/access.log"
CPP_PATH = "/home/user/log_analyzer.cpp"
EXE_PATH = "/home/user/log_analyzer"
CSV_PATH = "/home/user/endpoint_stats.csv"
DB_PATH = "/home/user/log_stats.db"

CANONICAL_LOG = """[2023-10-24T12:00:00Z] 192.168.1.10 GET /api/users HTTP/1.1 200 45
[2023-10-24T12:00:01Z] 10.0.0.5 POST /api/login HTTP/1.1 200 120
[2023-10-24T12:00:02Z] 192.168.1.11 GET /api/users HTTP/1.1 500 200
[2023-10-24T12:00:03Z] 192.168.1.10 INVALID /api/users HTTP/1.1 200 50
[2023-10-24T12:00:04Z] 10.0.0.6 GET /api/data HTTP/1.1 200 -10
[2023-10-24T12:00:05Z] 10.0.0.7 GET /api/data HTTP/1.1 200 30
[2023-10-24T12:00:06Z] malformed line here missing fields
[2023-10-24T12:00:07Z] 192.168.1.12 GET /api/users HTTP/1.1 200 55
[2023-10-24T12:00:08Z] 10.0.0.8 PUT /api/data HTTP/1.1 201 40
[2023-10-24T12:00:09Z] 10.0.0.9 DELETE /api/old HTTP/1.1 204 15
[2023-10-24T12:00:10Z] 10.0.0.10 GET /api/users HTTP/1.1 xyz 100
"""


def compute_expected_stats_from_text(log_text):
    stats = {}
    valid_methods = {"GET", "POST", "PUT", "DELETE"}

    for line in io.StringIO(log_text):
        parts = line.strip().split()
        if len(parts) != 7:
            continue

        _, _, method, endpoint, _, status_code_str, response_time_str = parts

        if method not in valid_methods:
            continue

        try:
            status_code = int(status_code_str)
            if status_code <= 0:
                continue
        except ValueError:
            continue

        try:
            response_time = int(response_time_str)
            if response_time < 0:
                continue
        except ValueError:
            continue

        if endpoint not in stats:
            stats[endpoint] = {"total": 0, "success": 0, "time_sum": 0}

        stats[endpoint]["total"] += 1
        if status_code == 200:
            stats[endpoint]["success"] += 1
        stats[endpoint]["time_sum"] += response_time

    expected_csv = []
    for ep in sorted(stats.keys()):
        total = stats[ep]["total"]
        success = stats[ep]["success"]
        avg_time = stats[ep]["time_sum"] // total
        expected_csv.append({
            "endpoint": ep,
            "total_requests": str(total),
            "success_requests": str(success),
            "avg_response_time": str(avg_time),
        })
    return expected_csv


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def install_log(contents):
    if os.path.lexists(LOG_PATH):
        remove_path(LOG_PATH)
    with open(LOG_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(contents)
    os.chmod(LOG_PATH, 0o666)


def run_analyzer(log_text):
    install_log(log_text)
    if os.path.lexists(CSV_PATH):
        remove_path(CSV_PATH)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", EXE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Analyzer exited with status {result.returncode}. "
        f"stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    assert os.path.isfile(CSV_PATH), "Analyzer did not create endpoint_stats.csv."


def read_csv_rows():
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == [
            "endpoint", "total_requests", "success_requests", "avg_response_time"
        ], "CSV header does not match expected exact header."
        return list(reader)


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.lexists(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    source_info = os.lstat(CPP_PATH)
    assert stat.S_ISREG(source_info.st_mode), "C++ source must be a regular file."

    if os.path.lexists(EXE_PATH):
        remove_path(EXE_PATH)
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", EXE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Compilation failed with status {result.returncode}. "
        f"stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    assert os.path.isfile(EXE_PATH), "Compilation did not produce the analyzer executable."
    assert os.access(EXE_PATH, os.X_OK), "Compiled analyzer is not executable."
    run_analyzer(CANONICAL_LOG)
    yield


def test_files_exist():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"CSV file {CSV_PATH} does not exist."
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(CPP_PATH).st_mode), "C++ source is not a regular file."
    assert stat.S_ISREG(os.lstat(EXE_PATH).st_mode), "Executable is not a regular file."
    assert os.access(EXE_PATH, os.X_OK), "Analyzer executable is not executable."
    assert stat.S_ISREG(os.lstat(CSV_PATH).st_mode), "CSV output is not a regular file."
    assert stat.S_ISREG(os.lstat(DB_PATH).st_mode), "Database is not a regular file."


def test_csv_content():
    expected_rows = compute_expected_stats_from_text(CANONICAL_LOG)
    actual_rows = read_csv_rows()

    assert len(actual_rows) == len(expected_rows), "Number of rows in CSV does not match expected."

    for actual, expected in zip(actual_rows, expected_rows):
        assert actual["endpoint"] == expected["endpoint"], f"Expected endpoint {expected['endpoint']}, got {actual['endpoint']}"
        assert actual["total_requests"] == expected["total_requests"], f"Expected total_requests {expected['total_requests']} for {expected['endpoint']}"
        assert actual["success_requests"] == expected["success_requests"], f"Expected success_requests {expected['success_requests']} for {expected['endpoint']}"
        assert actual["avg_response_time"] == expected["avg_response_time"], f"Expected avg_response_time {expected['avg_response_time']} for {expected['endpoint']}"


def test_sqlite_db_content():
    expected_rows = compute_expected_stats_from_text(CANONICAL_LOG)

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='endpoint_stats';")
        assert cursor.fetchone() is not None, "Table 'endpoint_stats' does not exist in the database."

        cursor.execute("PRAGMA table_info(endpoint_stats);")
        columns = cursor.fetchall()
        col_dict = {col[1]: {"type": col[2].upper(), "pk": col[5]} for col in columns}

        assert "endpoint" in col_dict, "Column 'endpoint' missing in table schema."
        assert "TEXT" in col_dict["endpoint"]["type"], "Column 'endpoint' should be TEXT."
        assert col_dict["endpoint"]["pk"] == 1, "Column 'endpoint' should be the PRIMARY KEY."

        for num_col in ["total_requests", "success_requests", "avg_response_time"]:
            assert num_col in col_dict, f"Column '{num_col}' missing in table schema."
            assert "INT" in col_dict[num_col]["type"], f"Column '{num_col}' should be INTEGER."

        cursor.execute("SELECT endpoint, total_requests, success_requests, avg_response_time FROM endpoint_stats ORDER BY endpoint;")
        db_rows = cursor.fetchall()

        assert len(db_rows) == len(expected_rows), "Number of rows in database does not match expected."

        for db_row, expected in zip(db_rows, expected_rows):
            assert db_row[0] == expected["endpoint"], "Endpoint mismatch in DB."
            assert str(db_row[1]) == expected["total_requests"], f"total_requests mismatch for {expected['endpoint']} in DB."
            assert str(db_row[2]) == expected["success_requests"], f"success_requests mismatch for {expected['endpoint']} in DB."
            assert str(db_row[3]) == expected["avg_response_time"], f"avg_response_time mismatch for {expected['endpoint']} in DB."
    finally:
        conn.close()


def test_compiled_analyzer_on_unseen_inputs():
    token = secrets.token_hex(6)
    endpoints = [f"/verify/{token}/{name}" for name in ["alpha", "beta", "gamma", "zeta"]]
    methods = ["GET", "POST", "PUT", "DELETE"]
    lines = []

    for i in range(28):
        endpoint = endpoints[secrets.randbelow(len(endpoints))]
        method = methods[secrets.randbelow(len(methods))]
        status = [200, 200, 201, 204, 404, 503][secrets.randbelow(6)]
        response = secrets.randbelow(5000)
        lines.append(
            f"[2026-01-01T00:00:{i:02d}Z] 10.2.3.{i + 1} {method} {endpoint} HTTP/1.1 {status} {response}"
        )

    lines.extend([
        f"[2026-01-02T00:00:00Z] 1.1.1.1 PATCH {endpoints[0]} HTTP/1.1 200 10",
        f"[2026-01-02T00:00:01Z] 1.1.1.2 GET {endpoints[1]} HTTP/1.1 0 10",
        f"[2026-01-02T00:00:02Z] 1.1.1.3 POST {endpoints[1]} HTTP/1.1 -3 10",
        f"[2026-01-02T00:00:03Z] 1.1.1.4 PUT {endpoints[2]} HTTP/1.1 nope 10",
        f"[2026-01-02T00:00:04Z] 1.1.1.5 DELETE {endpoints[2]} HTTP/1.1 200 -1",
        f"[2026-01-02T00:00:05Z] 1.1.1.6 GET {endpoints[3]} HTTP/1.1 200 bad",
        "too few fields",
        f"[2026-01-02T00:00:06Z] 1.1.1.7 GET {endpoints[0]} HTTP/1.1 200 10 extra",
    ])
    challenge_log = "\n".join(lines) + "\n"

    try:
        run_analyzer(challenge_log)
        assert read_csv_rows() == compute_expected_stats_from_text(challenge_log), \
            "Analyzer output is incorrect for an unseen mixed-validity log."

        invalid_only = "\n".join([
            "bad line",
            f"[2026-02-01T00:00:00Z] 2.2.2.2 TRACE /none/{token} HTTP/1.1 200 5",
            f"[2026-02-01T00:00:01Z] 2.2.2.3 GET /none/{token} HTTP/1.1 invalid 5",
            f"[2026-02-01T00:00:02Z] 2.2.2.4 GET /none/{token} HTTP/1.1 200 -5",
        ]) + "\n"
        run_analyzer(invalid_only)
        assert read_csv_rows() == [], "A log with no valid records must produce only the CSV header."
    finally:
        run_analyzer(CANONICAL_LOG)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
