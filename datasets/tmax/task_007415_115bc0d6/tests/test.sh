#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/process_audit.sh"
LOG_PATH = "/home/user/cm_audit.log"
DB_PATH = "/home/user/config_tracking.db"


def parse_expected(log_text):
    records = []
    current = None

    for line in log_text.splitlines():
        if line == "BEGIN_RECORD":
            current = {"timestamp": None, "action": None, "details": None}
        elif current is not None and line.startswith("TIMESTAMP:"):
            current["timestamp"] = line.split(":", 1)[1].lstrip()
        elif current is not None and line.startswith("ACTION:"):
            current["action"] = line.split(":", 1)[1].lstrip()
        elif current is not None and line.startswith("DETAILS:"):
            current["details"] = line.split(":", 1)[1].lstrip()
        elif line == "END_RECORD" and current is not None:
            if all(current[field] is not None for field in ("timestamp", "action", "details")):
                details = re.sub(r"(?<!\S)password=[^\s]*", "password=***", current["details"])
                details = re.sub(
                    r"(?<!\S)ip=(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}(?=\s|$)",
                    r"ip=\1.XXX",
                    details,
                )
                records.append((current["timestamp"], current["action"], details))
            current = None

    return records


def remove_database():
    for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", DB_PATH + "-journal"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_submission():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_exact_database(expected):
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a file"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log';")
        assert cursor.fetchone() is not None, "Table 'audit_log' does not exist in the database."

        cursor.execute("PRAGMA table_info(audit_log)")
        columns = [(row[1], row[2].upper()) for row in cursor.fetchall()]
        assert columns == [
            ("timestamp", "TEXT"),
            ("action", "TEXT"),
            ("details", "TEXT"),
        ], f"Unexpected audit_log schema: {columns}"

        cursor.execute("SELECT timestamp, action, details FROM audit_log")
        actual = cursor.fetchall()
        assert Counter(actual) == Counter(expected), (
            f"Database rows do not exactly match the extracted and masked log records. "
            f"Expected {expected!r}, found {actual!r}."
        )
        assert len(actual) == len(expected), "Database contains duplicate or extra rows."
    finally:
        conn.close()


def test_pipeline_execution_and_output():
    # Preserve the original verifier's script-kind assertions.
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"

    with open(LOG_PATH, "rb") as handle:
        original_log_bytes = handle.read()
    original_log_text = original_log_bytes.decode("utf-8")
    original_expected = parse_expected(original_log_text)

    with tempfile.TemporaryDirectory() as tempdir:
        validated_original_db = os.path.join(tempdir, "validated_original.db")
        try:
            # Do not trust a database left by the agent: recreate it by executing the artifact.
            remove_database()
            run_submission()
            assert_exact_database(original_expected)

            # Preserve the original verifier's aggregate and specific assertions.
            conn = sqlite3.connect(DB_PATH)
            try:
                cursor = conn.cursor()
                cursor.execute("SELECT COUNT(*) FROM audit_log;")
                assert cursor.fetchone()[0] == 3, "Expected 3 rows in audit_log."

                cursor.execute("SELECT COUNT(*) FROM audit_log WHERE details LIKE '%password=***%';")
                assert cursor.fetchone()[0] == 2, "Expected 2 rows with masked passwords."

                cursor.execute("SELECT COUNT(*) FROM audit_log WHERE details LIKE '%ip=%.XXX%';")
                assert cursor.fetchone()[0] == 3, "Expected 3 rows with masked IPs."

                cursor.execute("SELECT action FROM audit_log WHERE timestamp='2023-10-27T10:05:12Z';")
                row = cursor.fetchone()
                assert row is not None, "Record with timestamp '2023-10-27T10:05:12Z' not found."
                assert row[0] == "UPDATE_FW", "Expected UPDATE_FW for the checked timestamp."

                cursor.execute(
                    "SELECT COUNT(*) FROM audit_log "
                    "WHERE details LIKE '%password=%' AND details NOT LIKE '%password=***%';"
                )
                assert cursor.fetchone()[0] == 0, "Found rows with unmasked passwords."
            finally:
                conn.close()

            shutil.copy2(DB_PATH, validated_original_db)

            # Exercise the script on an unpredictable, independently parsed input so a
            # hard-coded database or fixed three-row implementation cannot pass.
            token = uuid.uuid4().hex[:12]
            dynamic_log = f"""warning before records

BEGIN_RECORD
TIMESTAMP: 2041-04-03T01:02:03Z
ACTION: CREATE_{token}
DETAILS: account=user_{token} password=S3cret!{token} ip=203.0.113.47 role=ops
END_RECORD

ignored system warning
BEGIN_RECORD
TIMESTAMP: 2041-04-03T02:03:04Z
ACTION: FIREWALL_{token}
DETAILS: rule=deny port=443 ip=8.8.4.4 ticket={token}
END_RECORD

BEGIN_RECORD
TIMESTAMP: 2041-04-03T03:04:05Z
ACTION: ROTATE_{token}
DETAILS: username=admin password=next-{token} note=scheduled ip=10.20.30.255
END_RECORD

BEGIN_RECORD
TIMESTAMP: 2041-04-03T04:05:06Z
ACTION: INSPECT_{token}
DETAILS: service=cm status=healthy marker={token}
END_RECORD
trailing noise
"""
            dynamic_expected = parse_expected(dynamic_log)
            with open(LOG_PATH, "w", encoding="utf-8") as handle:
                handle.write(dynamic_log)

            remove_database()
            run_submission()
            assert_exact_database(dynamic_expected)

            assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} disappeared after execution"
            assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is no longer executable"
        finally:
            with open(LOG_PATH, "wb") as handle:
                handle.write(original_log_bytes)
            remove_database()
            if os.path.exists(validated_original_db):
                shutil.copy2(validated_original_db, DB_PATH)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
