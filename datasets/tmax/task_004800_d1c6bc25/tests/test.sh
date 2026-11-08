#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import datetime as dt
import json
import os
import secrets
import stat
import subprocess

HOME = "/home/user"
INPUT = os.path.join(HOME, "app_logs.jsonl")
QUARANTINE = os.path.join(HOME, "quarantine.jsonl")
STATS = os.path.join(HOME, "hourly_stats.csv")


def check_original_outputs():
    assert os.path.exists(QUARANTINE), f"The file {QUARANTINE} does not exist."
    assert os.path.isfile(QUARANTINE), f"The path {QUARANTINE} is not a regular file."

    with open(QUARANTINE, "r") as f:
        lines = f.readlines()

    assert len(lines) == 1, f"Expected exactly 1 line in {QUARANTINE}, found {len(lines)}."
    expected_line = '{"event_id": "6", "timestamp": "2023-10-01T10:00:00Z", "payload": "bad unicode \\u001Z", "response_time": 10.0}'
    assert lines[0].strip() == expected_line, "The quarantined line does not match the expected malformed line."

    assert os.path.exists(STATS), f"The file {STATS} does not exist."
    assert os.path.isfile(STATS), f"The path {STATS} is not a regular file."

    with open(STATS, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, f"The file {STATS} is empty."
    expected_headers = ["hour", "event_count", "avg_response_time"]
    assert rows[0] == expected_headers, f"Expected headers {expected_headers}, but got {rows[0]}."

    expected_data = [
        ["2023-10-01T10:00:00Z", "2", "150.00"],
        ["2023-10-01T11:00:00Z", "2", "100.00"],
        ["2023-10-01T12:00:00Z", "1", "300.00"],
    ]
    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, found {len(data_rows)}."
    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."


def script_candidates():
    excluded_dirs = {".cache", ".local", ".venv", "venv", "__pycache__"}
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in excluded_dirs]
        for name in files:
            path = os.path.join(root, name)
            if path in {INPUT, QUARANTINE, STATS}:
                continue
            try:
                mode = os.lstat(path).st_mode
                if not stat.S_ISREG(mode):
                    continue
                is_python = name.endswith(".py")
                if not is_python:
                    with open(path, "rb") as f:
                        first = f.readline(256).lower()
                    is_python = first.startswith(b"#!") and b"python" in first
                if is_python:
                    found.append(path)
            except (OSError, UnicodeError):
                continue
    return sorted(found, key=lambda p: (p.count(os.sep), p))


def make_fixture():
    token = secrets.token_hex(8)
    base_epoch = 1704067200 + secrets.randbelow(12000) * 3600
    base = dt.datetime.fromtimestamp(base_epoch, dt.timezone.utc)

    def iso(hour_offset, minute):
        value = base + dt.timedelta(hours=hour_offset, minutes=minute)
        return value.strftime("%Y-%m-%dT%H:%M:%SZ")

    a = 80 + secrets.randbelow(40) + 0.20
    b = 180 + secrets.randbelow(40) + 0.40
    c = 45 + secrets.randbelow(30) + 0.10
    d = 125 + secrets.randbelow(30) + 0.30
    e = 260 + secrets.randbelow(30) + 0.37

    payload_one = {"user": "alpha-" + token, "action": "login"}
    payload_two = {"user": "beta-" + token, "action": "view", "meta": {"x": 1, "y": 2}}
    payload_two_reordered = {"meta": {"y": 2, "x": 1}, "action": "view", "user": "beta-" + token}
    payload_three = {"user": "gamma-" + token, "action": "logout"}
    payload_four = {"user": "delta-" + token, "action": "login"}
    payload_five = {"user": "epsilon-" + token, "items": [1, 2, 3]}

    records = [
        {"event_id": token + "-1", "timestamp": iso(0, 11), "payload": payload_one, "response_time": a},
        {"event_id": token + "-2", "timestamp": base_epoch + 47 * 60, "payload": payload_two, "response_time": b},
        {"event_id": token + "-3", "timestamp": iso(1, 2), "payload": payload_two_reordered, "response_time": 9999.99},
        {"event_id": token + "-4", "timestamp": iso(1, 9), "payload": payload_three, "response_time": c},
        {"event_id": token + "-5", "timestamp": base_epoch + 3600 + 53 * 60, "payload": payload_four, "response_time": d},
        {"event_id": token + "-6", "timestamp": iso(2, 1), "payload": payload_five, "response_time": e},
        {"event_id": token + "-7", "timestamp": iso(2, 44), "payload": {"items": [1, 2, 3], "user": "epsilon-" + token}, "response_time": 1.0},
    ]

    malformed_one = '{"event_id":"bad-' + token + '","payload":"broken \\u12G4"}\n'
    malformed_two = ' {"event_id":"truncated-' + token + '","timestamp":12345\n'
    lines = [
        json.dumps(records[0], separators=(",", ":")) + "\n",
        malformed_one,
        json.dumps(records[1]) + "\n",
        json.dumps(records[2]) + "\n",
        json.dumps(records[3]) + "\n",
        malformed_two,
        json.dumps(records[4]) + "\n",
        json.dumps(records[5]) + "\n",
        json.dumps(records[6]) + "\n",
    ]

    expected_rows = [
        [base.strftime("%Y-%m-%dT%H:00:00Z"), "2", f"{(a + b) / 2:.2f}"],
        [(base + dt.timedelta(hours=1)).strftime("%Y-%m-%dT%H:00:00Z"), "2", f"{(c + d) / 2:.2f}"],
        [(base + dt.timedelta(hours=2)).strftime("%Y-%m-%dT%H:00:00Z"), "1", f"{e:.2f}"],
    ]
    return "".join(lines).encode(), (malformed_one + malformed_two).encode(), expected_rows


def dynamic_output_is_correct(expected_quarantine, expected_rows):
    if not os.path.isfile(QUARANTINE) or not os.path.isfile(STATS):
        return False
    with open(QUARANTINE, "rb") as f:
        if f.read() != expected_quarantine:
            return False
    try:
        with open(STATS, "r", newline="") as f:
            rows = list(csv.reader(f))
    except (OSError, UnicodeError, csv.Error):
        return False
    return rows == [["hour", "event_count", "avg_response_time"]] + expected_rows


def check_script_behavior():
    candidates = script_candidates()
    assert candidates, "No Python processing script was created under /home/user."
    fixture, expected_quarantine, expected_rows = make_fixture()
    failures = []

    for candidate in candidates:
        with open(INPUT, "wb") as f:
            f.write(fixture)
        for output in (QUARANTINE, STATS):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        try:
            result = subprocess.run(
                ["python3", candidate],
                cwd=HOME,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append(f"{candidate}: {exc}")
            continue

        if result.returncode == 0 and dynamic_output_is_correct(expected_quarantine, expected_rows):
            return
        failures.append(f"{candidate}: exit status {result.returncode} or incorrect outputs")

    raise AssertionError("No submitted Python script correctly processed a fresh fixture. " + "; ".join(failures))


check_original_outputs()
check_script_behavior()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
