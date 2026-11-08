#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import tempfile
import uuid
from collections import Counter

import pytest

CRASH_URL = "https://this-is-a-very-long-url-that-will-cause-a-buffer-overflow.com/ping"

EXPECTED_URLS = {
    "http://example.com/api/v1/health",
    "https://internal-service.local/ping",
    "https://this-is-a-very-long-url-that-will-cause-a-buffer-overflow.com/ping",
    "http://localhost:8080/metrics",
}


def test_crash_cause_file():
    path = "/home/user/crash_cause.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == CRASH_URL, f"File {path} does not contain the correct crashing URL."


def test_recovered_urls_file():
    path = "/home/user/recovered_urls.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert set(lines) == EXPECTED_URLS, f"File {path} does not contain the exact expected URLs."
    assert len(lines) == len(EXPECTED_URLS), f"File {path} contains duplicate or incorrect number of URLs."


def test_database_recovery_and_consistency():
    db_path = "/home/user/monitor.db"
    wal_path = db_path + "-wal"

    assert os.path.isfile(db_path), f"Database {db_path} does not exist."
    assert not (os.path.exists(wal_path) and os.path.getsize(wal_path) > 32), (
        "Database still has an active, non-empty WAL and was not fully recovered."
    )

    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        integrity = conn.execute("PRAGMA integrity_check;").fetchall()
        assert integrity == [("ok",)], f"Database integrity check failed: {integrity}"

        rows = conn.execute("SELECT url FROM endpoints;").fetchall()
        database_urls = [row[0] for row in rows]
        assert set(database_urls) == EXPECTED_URLS, (
            "Recovered database does not contain all expected endpoint URLs."
        )
        assert len(database_urls) == len(EXPECTED_URLS), (
            "Recovered database contains duplicate or unexpected endpoint rows."
        )
    finally:
        conn.close()

    with open("/home/user/recovered_urls.txt", "r") as f:
        recovered_urls = [line.strip() for line in f if line.strip()]
    assert Counter(recovered_urls) == Counter(database_urls), (
        "recovered_urls.txt does not match the recovered endpoints table."
    )


def test_uptime_monitor_script_execution():
    script_path = "/home/user/uptime-monitor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    try:
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {script_path} timed out during execution.")

    assert result.returncode == 0, (
        f"Script {script_path} failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )

    expected_skip_msg = f"Skipped: {CRASH_URL}"
    assert expected_skip_msg in result.stdout, (
        f"Script output did not contain the expected skip message: '{expected_skip_msg}'\n"
        f"Stdout: {result.stdout}"
    )


def _url_of_length(length, marker):
    prefix = "http://x/"
    payload = (marker * ((length - len(prefix)) // len(marker) + 1))[: length - len(prefix)]
    value = prefix + payload
    assert len(value) == length
    return value


def test_general_length_check_and_helper_invocation():
    script_path = "/home/user/uptime-monitor.sh"
    db_path = "/home/user/monitor.db"
    helper_path = "/home/user/check_status"
    token = uuid.uuid4().hex
    short_59 = _url_of_length(59, "a" + token)
    boundary_60 = _url_of_length(60, "b" + token)
    long_61 = _url_of_length(61, "c" + token)
    long_79 = _url_of_length(79, "d" + token)
    processed_url = _url_of_length(40, "e" + token)
    log_path = f"/tmp/check-status-calls-{uuid.uuid4().hex}.log"

    with tempfile.TemporaryDirectory(prefix="uptime-verifier-") as backup_dir:
        original_paths = [db_path, db_path + "-wal", db_path + "-shm", helper_path]
        moved = {}
        try:
            for path in original_paths:
                if os.path.lexists(path):
                    backup = os.path.join(backup_dir, os.path.basename(path))
                    os.replace(path, backup)
                    moved[path] = backup

            conn = sqlite3.connect(db_path)
            try:
                conn.execute(
                    "CREATE TABLE endpoints (id INTEGER PRIMARY KEY, url TEXT, status TEXT);"
                )
                conn.executemany(
                    "INSERT INTO endpoints (url, status) VALUES (?, ?);",
                    [
                        (short_59, "pending"),
                        (boundary_60, "pending"),
                        (long_61, "pending"),
                        (long_79, "pending"),
                        (processed_url, "processed"),
                    ],
                )
                conn.commit()
            finally:
                conn.close()

            with open(helper_path, "w") as f:
                f.write(
                    "#!/bin/bash\n"
                    f"printf '%s\\n' \"$1\" >> '{log_path}'\n"
                    "printf 'Successfully checked %s\\n' \"$1\"\n"
                )
            os.chmod(helper_path, 0o755)

            try:
                result = subprocess.run(
                    [script_path], capture_output=True, text=True, timeout=10
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Script {script_path} timed out on generated test URLs.")

            assert result.returncode == 0, (
                f"Script failed on generated URLs with code {result.returncode}.\n"
                f"Stdout: {result.stdout}\nStderr: {result.stderr}"
            )

            if os.path.exists(log_path):
                with open(log_path, "r") as f:
                    calls = [line.rstrip("\n") for line in f]
            else:
                calls = []

            assert Counter(calls) == Counter([short_59, boundary_60]), (
                "check_status must be invoked exactly once for each pending URL of length "
                "60 or less, and never for longer URLs. "
                f"Observed calls: {calls}"
            )

            output_lines = result.stdout.splitlines()
            for long_url in (long_61, long_79):
                expected = f"Skipped: {long_url}"
                assert output_lines.count(expected) == 1, (
                    f"Expected exactly one output line '{expected}'.\n"
                    f"Stdout: {result.stdout}"
                )
            for short_url in (short_59, boundary_60):
                assert f"Skipped: {short_url}" not in output_lines, (
                    f"URL of length {len(short_url)} was incorrectly skipped."
                )
        finally:
            for path in [db_path, db_path + "-wal", db_path + "-shm", helper_path]:
                if os.path.lexists(path):
                    os.unlink(path)
            if os.path.exists(log_path):
                os.unlink(log_path)
            for path, backup in moved.items():
                os.replace(backup, path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
