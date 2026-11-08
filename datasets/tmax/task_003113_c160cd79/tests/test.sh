#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import sqlite3
import stat
import string
import subprocess
from decimal import Decimal, ROUND_DOWN, ROUND_HALF_UP

import pytest

SCANNER = "/home/user/scanner.sh"
REPORT = "/home/user/report.txt"
RAW = "/home/user/raw_intel.bin"
DB = "/home/user/intel.db"


def file_hash(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).digest()


def run_scanner():
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    return subprocess.run(
        ["bash", SCANNER],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


@pytest.fixture(scope="module")
def original_run():
    assert os.path.exists(SCANNER), f"Expected scanner script {SCANNER} was not found."
    assert stat.S_ISREG(os.lstat(SCANNER).st_mode), "scanner.sh must be a regular file."

    db_before = file_hash(DB)
    raw_before = file_hash(RAW)
    result = run_scanner()

    assert result.returncode == 0, (
        f"bash {SCANNER} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert file_hash(DB) == db_before, "scanner.sh modified intel.db."
    assert file_hash(RAW) == raw_before, "scanner.sh modified raw_intel.bin."
    return result


def test_report_exists(original_run):
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Expected report file {report_path} was not found."


def test_report_content(original_run):
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Expected report file {report_path} was not found."

    with open(report_path, "r") as f:
        content = f.read()

    # Check TX99 score (4.28 or 4.29)
    assert re.search(r"TX99:4\.2[89]", content), "TX99 score is missing or incorrect in report.txt. Expected 4.28 or 4.29."

    # Check TZ88 score (8.14 or 8.15)
    assert re.search(r"TZ88:8\.1[45]", content), "TZ88 score is missing or incorrect in report.txt. Expected 8.14 or 8.15."

    # Check QW12 score (2.25)
    assert re.search(r"QW12:2\.25", content), "QW12 score is missing or incorrect in report.txt. Expected 2.25."


def test_scanner_handles_fresh_corrupted_input_and_database(original_run):
    original_db = open(DB, "rb").read()
    original_raw = open(RAW, "rb").read()

    def random_id():
        return "".join(secrets.choice(string.ascii_uppercase) for _ in range(2)) + f"{secrets.randbelow(100):02d}"

    ids = set()
    while len(ids) < 3:
        candidate = random_id()
        if candidate not in {"TX99", "TZ88", "QW12"}:
            ids.add(candidate)
    ids = list(ids)

    rows = []
    for threat_id in ids:
        base_tenths = 21 + secrets.randbelow(780)
        mult_tenths = 11 + secrets.randbelow(90)
        rows.append((threat_id, base_tenths, mult_tenths))

    try:
        os.remove(DB)
        conn = sqlite3.connect(DB)
        conn.execute("CREATE TABLE threats (id TEXT, base_score REAL, multiplier REAL)")
        for threat_id, base_tenths, mult_tenths in rows:
            conn.execute(
                "INSERT INTO threats VALUES (?, ?, ?)",
                (threat_id, base_tenths / 10.0, mult_tenths / 10.0),
            )
        conn.commit()
        conn.close()

        corrupted = b"".join(
            b"".join(bytes((byte, 0)) for byte in threat_id.encode("ascii")) + b"\n"
            for threat_id, _, _ in rows
        )
        with open(RAW, "wb") as f:
            f.write(corrupted)

        dynamic_db_hash = file_hash(DB)
        dynamic_raw_hash = file_hash(RAW)
        result = run_scanner()
        assert result.returncode == 0, (
            f"scanner.sh failed on fresh test data.\nstdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
        assert file_hash(DB) == dynamic_db_hash, "scanner.sh modified the test database."
        assert file_hash(RAW) == dynamic_raw_hash, "scanner.sh modified the corrupted input file."
        assert os.path.isfile(REPORT), "scanner.sh did not create report.txt."

        with open(REPORT, "r") as f:
            lines = f.read().splitlines()

        assert len(lines) == len(rows), "report.txt must contain exactly one result per input threat ID."
        actual = {}
        for line in lines:
            match = re.fullmatch(r"([A-Z]{2}[0-9]{2}):(-?[0-9]+\.[0-9]{2})", line)
            assert match, f"Malformed report line: {line!r}"
            assert match.group(1) not in actual, f"Duplicate threat ID in report: {match.group(1)}"
            actual[match.group(1)] = match.group(2)

        assert set(actual) == set(ids), "The report IDs do not match the sanitized input IDs."
        for threat_id, base_tenths, mult_tenths in rows:
            exact = (Decimal(base_tenths) / Decimal(10)) * (Decimal(mult_tenths) / Decimal(10)) / Decimal(7)
            accepted = {
                format(exact.quantize(Decimal("0.01"), rounding=ROUND_DOWN), ".2f"),
                format(exact.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP), ".2f"),
            }
            assert actual[threat_id] in accepted, (
                f"Incorrect score for {threat_id}: got {actual[threat_id]}, expected one of {sorted(accepted)}"
            )
    finally:
        with open(DB, "wb") as f:
            f.write(original_db)
        with open(RAW, "wb") as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
