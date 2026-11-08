#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import io
import json
import os
import secrets
import sqlite3
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

VENDOR = "/app/vendor/sqlite_bulk_loader-1.0.0"
SANITIZER = "/home/user/sanitize_logs"
DB_PATH = "/home/user/metrics.db"


def run_sanitizer(input_data):
    return subprocess.run(
        [SANITIZER], input=input_data, capture_output=True, text=True, timeout=15
    )


def test_vendored_package_fixed():
    makefile_path = os.path.join(VENDOR, "Makefile")
    load_csv_path = os.path.join(VENDOR, "load_csv.sh")

    assert os.path.isfile(makefile_path), "Makefile is missing."
    assert os.path.isfile(load_csv_path), "load_csv.sh is missing."

    with open(load_csv_path, "r") as f:
        content = f.read()
    assert "/root/forbidden.db" not in content, "load_csv.sh still contains the forbidden DB_PATH."

    result = subprocess.run(
        ["make", "install"], cwd=VENDOR, capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"make install failed: {result.stderr}"

    test_csv = "/tmp/test_load.csv"
    with open(test_csv, "w") as f:
        f.write("2023-10-01T12:00:00Z,999,test,test_msg\n")

    result = subprocess.run(
        ["./load_csv.sh", test_csv], cwd=VENDOR,
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"load_csv.sh failed: {result.stderr}"
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} was not created by load_csv.sh."

    result = subprocess.run(
        ["sqlite3", DB_PATH, "SELECT * FROM logs WHERE user_id=999;"],
        capture_output=True, text=True, timeout=15
    )
    assert "2023-10-01T12:00:00Z|999|test|test_msg" in result.stdout, \
        "Data was not correctly loaded into the database."


def test_loader_uses_arbitrary_csv_input():
    if os.path.lexists(DB_PATH):
        os.remove(DB_PATH)

    token = secrets.token_hex(10)
    rows = [
        ["2041-02-03T04:05:06Z", secrets.randbelow(800000000) + 100000000,
         f"action_{token}", f"message_{token}"],
        ["1998-11-12T13:14:15Z", secrets.randbelow(800000000) + 100000000,
         f"comma,{token}", f'quoted "{token}", value'],
        ["2027-07-08T09:10:11Z", secrets.randbelow(800000000) + 100000000,
         f"logout_{token}", f"unicode café {token}"],
    ]
    path = f"/tmp/load_{secrets.token_hex(8)}.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)

    result = subprocess.run(
        ["./load_csv.sh", path], cwd=VENDOR,
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"load_csv.sh failed on generated CSV: {result.stderr}"
    assert os.path.isfile(DB_PATH), "Loader did not create /home/user/metrics.db"

    con = sqlite3.connect(DB_PATH)
    try:
        columns = [r[1] for r in con.execute("PRAGMA table_info(logs)")]
        assert columns == ["timestamp", "user_id", "action", "message"]
        actual = con.execute(
            "SELECT timestamp, user_id, action, message FROM logs ORDER BY rowid"
        ).fetchall()
    finally:
        con.close()

    expected = [(r[0], r[1], r[2], r[3]) for r in rows]
    assert actual == expected, "Loader did not import the generated CSV rows exactly"


def test_sanitizer_executable():
    assert os.path.isfile(SANITIZER), f"Sanitizer not found at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer at {SANITIZER} is not executable."


def test_sanitizer_clean_corpus():
    clean_files = glob.glob("/app/corpora/clean/*.jsonl")
    assert len(clean_files) > 0, "No clean corpus files found."
    failed_files = []

    for file_path in clean_files:
        with open(file_path, "r") as f:
            input_data = f.read()

        result = run_sanitizer(input_data)
        if result.returncode != 0:
            failed_files.append(os.path.basename(file_path))
            continue

        output_lines = [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]
        input_lines = [line.strip() for line in input_data.strip().split("\n") if line.strip()]

        if len(output_lines) != len(input_lines):
            failed_files.append(os.path.basename(file_path))
            continue

        if os.path.basename(file_path) == "1.jsonl":
            assert output_lines[0] == "2023-10-01T12:00:00Z,1,login,Success", \
                f"Unexpected output: {output_lines[0]}"
            assert output_lines[1] == "2023-10-01T12:00:00Z,2,logout,Normal A logout", \
                f"Unexpected output: {output_lines[1]}"

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified/failed: "
            + ", ".join(failed_files)
        )


def test_sanitizer_evil_corpus():
    evil_files = glob.glob("/app/corpora/evil/*.jsonl")
    assert len(evil_files) > 0, "No evil corpus files found."
    bypassed_files = []

    for file_path in evil_files:
        with open(file_path, "r") as f:
            input_data = f.read()

        result = run_sanitizer(input_data)
        output_lines = [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]
        if len(output_lines) > 0:
            bypassed_files.append(os.path.basename(file_path))

    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: "
            + ", ".join(bypassed_files)
        )


def test_sanitizer_generated_formats_and_filtering():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(12)
    base = datetime.fromtimestamp(rng.randrange(978307200, 2051222400), timezone.utc)
    base = base.replace(microsecond=0)

    valid = []
    expected = []

    cases = []
    dt0 = base
    cases.append((int(dt0.timestamp()), dt0))

    dt1 = base + timedelta(seconds=137)
    cases.append((dt1.strftime("%Y-%m-%dT%H:%M:%SZ"), dt1))

    dt2 = base + timedelta(seconds=274)
    offset = timezone(timedelta(hours=5, minutes=30))
    cases.append((dt2.astimezone(offset).isoformat(timespec="seconds"), dt2))

    dt3 = base + timedelta(seconds=411)
    cases.append((dt3.strftime("%Y-%m-%dT%H:%M:%S"), dt3))

    for i, (timestamp_value, utc_dt) in enumerate(cases):
        user_id = rng.randrange(10000, 2000000000)
        action = f"action_{i}_{token}"
        message = f'message {i}, quoted "value" {token}'
        valid.append({
            "timestamp": timestamp_value,
            "user_id": user_id,
            "action": action,
            "message": message,
        })
        expected.append([
            utc_dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            str(user_id), action, message,
        ])

    good_lines = [json.dumps(item, ensure_ascii=False) for item in valid]
    common = {
        "timestamp": base.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "user_id": rng.randrange(10000, 2000000000),
        "action": f"bad_{token}",
    }

    esc_record = dict(common, message=f"escape {chr(27)} {token}")
    raw_lower_escape = json.dumps(esc_record)
    raw_upper_escape = raw_lower_escape.replace(
        chr(92) + "u001b", chr(92) + "u001B"
    )
    raw_literal_escape = raw_lower_escape.replace(chr(92) + "u001b", chr(27))
    raw_invalid_x = (
        '{"timestamp":"' + common["timestamp"] + '","user_id":' +
        str(common["user_id"]) + ',"action":"bad","message":"bad ' +
        chr(92) + 'x1b"}'
    )

    rejected = [
        raw_lower_escape,
        raw_upper_escape,
        raw_literal_escape,
        raw_invalid_x,
        json.dumps(dict(common, message=f"bad time {token}", timestamp="not-a-time")),
        json.dumps({"user_id": common["user_id"], "action": "missing", "message": token}),
        json.dumps(dict(common, message=token, user_id="not-an-integer")),
        json.dumps(dict(common, message=token, action=12345)),
        "{malformed json " + token,
    ]

    mixed = [good_lines[0], rejected[0], rejected[4], good_lines[1], rejected[1],
             rejected[5], good_lines[2], rejected[2], rejected[6], rejected[3],
             good_lines[3], rejected[7], rejected[8]]
    result = run_sanitizer("\n".join(mixed) + "\n")
    assert result.returncode == 0, f"Sanitizer failed on mixed generated input: {result.stderr}"

    try:
        actual = list(csv.reader(io.StringIO(result.stdout)))
    except csv.Error as exc:
        pytest.fail(f"Sanitizer output is not valid CSV: {exc}")

    assert actual == expected, \
        "Sanitizer did not normalize all generated valid records or failed to reject invalid ones"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
