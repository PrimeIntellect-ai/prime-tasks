#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
from decimal import Decimal, getcontext

import pytest


def test_recovered_database_exists_and_valid():
    recovered_db_path = "/home/user/recovered_metrics.db"
    assert os.path.isfile(recovered_db_path), f"Recovered database file {recovered_db_path} is missing."

    # Check if it's a valid SQLite database by checking the header
    with open(recovered_db_path, "rb") as f:
        header = f.read(16)
    assert header == b"SQLite format 3\x00", f"File {recovered_db_path} is not a valid SQLite database."

    # Verify that we can query it and the data is intact
    try:
        conn = sqlite3.connect(recovered_db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT latency FROM requests ORDER BY latency ASC")
        rows = cursor.fetchall()
        latencies = [row[0] for row in rows]
        assert latencies == [1000000001.0, 1000000002.0, 1000000003.0, 1000000004.0, 1000000005.0], "Recovered database does not contain the correct data."
    except sqlite3.Error as e:
        pytest.fail(f"Failed to read from recovered database: {e}")
    finally:
        if 'conn' in locals():
            conn.close()


def test_script_updated():
    script_path = "/home/user/calc_metrics.sh"
    assert os.path.isfile(script_path), f"Script file {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "/home/user/recovered_metrics.db" in content, "Script was not updated to use the recovered database."
    assert os.access(script_path, os.X_OK), "The metrics script is not executable."
    assert content.startswith("#!"), "The metrics script is not an executable script."


def test_variance_report_correct():
    report_path = "/home/user/variance_report.txt"
    assert os.path.isfile(report_path), f"Variance report file {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content == "2.50", f"Variance report contains '{content}', expected exactly '2.50'."


def test_script_executes_and_computes_stable_sample_variance():
    script_path = "/home/user/calc_metrics.sh"
    recovered_db_path = "/home/user/recovered_metrics.db"
    report_path = "/home/user/variance_report.txt"
    backup_path = f"/tmp/recovered_metrics_backup_{os.getpid()}.db"

    # Make a self-contained SQLite backup so the agent's required final artifacts
    # can be restored after exercising the script on verifier-generated inputs.
    source = sqlite3.connect(recovered_db_path)
    backup = sqlite3.connect(backup_path)
    try:
        source.backup(backup)
    finally:
        source.close()
        backup.close()

    with open(report_path, "rb") as f:
        original_report = f.read()

    getcontext().prec = 50

    def install_dataset(values):
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(recovered_db_path + suffix)
            except FileNotFoundError:
                pass
        conn = sqlite3.connect(recovered_db_path)
        try:
            conn.execute("CREATE TABLE requests (id INTEGER PRIMARY KEY, latency REAL)")
            conn.executemany("INSERT INTO requests(latency) VALUES (?)", [(float(v),) for v in values])
            conn.commit()
        finally:
            conn.close()

    try:
        datasets = []
        for n in (7, 9, 12):
            baseline = secrets.randbelow(400_000_000_000) + 100_000_000_000
            offsets = [secrets.randbelow(401) - 200 for _ in range(n)]
            # Ensure the data are nonconstant and not a reusable fixed fixture.
            if len(set(offsets)) == 1:
                offsets[-1] += 1
            datasets.append([baseline + offset for offset in offsets])

        for values in datasets:
            install_dataset(values)
            try:
                os.remove(report_path)
            except FileNotFoundError:
                pass

            result = subprocess.run(
                [script_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"calc_metrics.sh failed with exit code {result.returncode}: {result.stderr}"
            )
            assert os.path.isfile(report_path), "Running calc_metrics.sh did not create variance_report.txt."

            with open(report_path, "r") as f:
                content = f.read()
            assert re.fullmatch(r"-?\d+\.\d{2}\n?", content), (
                f"Variance report must contain only one number with exactly two decimal places; got {content!r}."
            )

            total = sum(values)
            n = len(values)
            numerator = sum((n * value - total) ** 2 for value in values)
            expected = Decimal(numerator) / Decimal(n * n * (n - 1))
            reported = Decimal(content.strip())
            assert abs(reported - expected) <= Decimal("0.0051"), (
                f"Script reported {reported}, but the sample variance for the supplied data is {expected}."
            )
    finally:
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(recovered_db_path + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup_path, recovered_db_path)
        try:
            os.remove(backup_path)
        except FileNotFoundError:
            pass
        with open(report_path, "wb") as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
