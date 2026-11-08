#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import stat
import subprocess
from collections import defaultdict

LOG_PATH = "/home/user/config_changes.log"
CSV_PATH = "/home/user/summary.csv"
SOURCE_PATH = "/home/user/tracker.cpp"
BINARY_PATH = "/home/user/tracker"
HEADERS = ["Hour_Bucket", "Total_Changes", "Unique_Targets", "Total_Lines_Added"]


def parse_and_process_log(log_path):
    if not os.path.exists(log_path):
        return []

    line_re = re.compile(r'^\[(.*?)\] User=(.*?) Action=(.*?) Target=(.*?) Details="(.*?)"$')
    lines_added_re = re.compile(r'lines_added:\s*(\d+)')
    last_accepted = {}
    buckets = defaultdict(lambda: {'changes': 0, 'targets': set(), 'lines_added': 0})

    with open(log_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = line_re.match(line)
            if not match:
                continue

            timestamp, user, action, target, details = match.groups()
            target = re.sub(r'/+', '/', target.lower())

            event_signature = (action, details)
            if target in last_accepted and last_accepted[target] == event_signature:
                continue
            last_accepted[target] = event_signature

            lines_match = lines_added_re.search(details)
            lines_added = int(lines_match.group(1)) if lines_match else 0

            if len(timestamp) >= 19 and timestamp[10] == 'T':
                hour_bucket = timestamp[:14] + "00:00Z"
            else:
                hour_bucket = timestamp

            buckets[hour_bucket]['changes'] += 1
            buckets[hour_bucket]['targets'].add(target)
            buckets[hour_bucket]['lines_added'] += lines_added

    return [[bucket, str(buckets[bucket]['changes']),
             str(len(buckets[bucket]['targets'])),
             str(buckets[bucket]['lines_added'])]
            for bucket in sorted(buckets)]


def read_and_check_csv(expected_data):
    assert os.path.isfile(CSV_PATH), f"Expected output file {CSV_PATH} does not exist."
    actual_data = []
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers == HEADERS, f"CSV headers are incorrect. Got: {headers}"
        for row in reader:
            if any(row):
                actual_data.append(row)

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} data rows, but found {len(actual_data)}."
    for i, (actual_row, expected_row) in enumerate(zip(actual_data, expected_data)):
        assert actual_row == expected_row, \
            f"Row {i + 1} mismatch. Expected {expected_row}, got {actual_row}."


def test_artifacts_exist_and_are_valid():
    assert os.path.isfile(SOURCE_PATH), f"Expected source file {SOURCE_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), "tracker.cpp must be a regular file."
    assert os.path.isfile(BINARY_PATH), f"Expected executable {BINARY_PATH} does not exist."
    binary_stat = os.lstat(BINARY_PATH)
    assert stat.S_ISREG(binary_stat.st_mode), "tracker must be a regular file."
    assert binary_stat.st_mode & 0o111, "tracker is not executable."
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "tracker must be a compiled ELF executable."

    rebuilt = "/tmp/tracker_rebuilt"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"tracker.cpp does not compile:\n{result.stderr}"


def test_summary_csv_exists():
    assert os.path.isfile(CSV_PATH), f"Expected output file {CSV_PATH} does not exist."


def test_summary_csv_content():
    assert os.path.isfile(LOG_PATH), f"Input log file {LOG_PATH} is missing, cannot verify."
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} is missing."
    read_and_check_csv(parse_and_process_log(LOG_PATH))


def make_dynamic_log(case_number):
    token = secrets.token_hex(6)
    year = 2024 + secrets.randbelow(2)
    month = 1 + secrets.randbelow(9)
    day = 10 + secrets.randbelow(10)
    h1 = 1 + secrets.randbelow(9)
    h2 = h1 + 2
    a = 1 + secrets.randbelow(40)
    b = 41 + secrets.randbelow(40)
    c = 81 + secrets.randbelow(40)

    date = f"{year:04d}-{month:02d}-{day:02d}"
    target_a_upper = f"/OPT///{token.upper()}//Service.CONF"
    target_a_lower = f"/opt/{token}/service.conf"
    target_b = f"/var//lib/{token}/state"
    target_c = f"Relative///{token.upper()}//Node"
    d1 = f"status: ok, lines_added: {a}"
    d2 = f"lines_added: {b}, phase: {case_number}"
    d3 = f"phase: changed, lines_added:   {c}"

    return "\n".join([
        f'[{date}T{h2:02d}:40:01Z] User=u1 Action=Update Target={target_b} Details="{d2}"',
        f'[{date}T{h1:02d}:05:02Z] User=u2 Action=Update Target={target_a_upper} Details="{d1}"',
        f'[{date}T{h1:02d}:11:03Z] User=u3 Action=Touch Target={target_b} Details="no numeric feature"',
        f'[{date}T{h1:02d}:20:04Z] User=u4 Action=Update Target={target_a_lower} Details="{d1}"',
        'this deliberately malformed line must be ignored',
        f'[{date}T{h2:02d}:02:05Z] User=u5 Action=Update Target={target_a_lower} Details="{d3}"',
        f'[{date}T{h2:02d}:03:06Z] User=u5 Action=Update Target={target_a_upper} Details="{d3}"',
        f'[{date}T{h1:02d}:59:07Z] User=u6 Action=Create Target={target_c} Details="prefix lines_added: {a + b}"',
        f'[{date}T{h2:02d}:10:08Z] User=u7 Action=Touch Target={target_b} Details="no numeric feature"',
        f'[{date}T{h2:02d}:55:09Z] User=u8 Action=Restart Target={target_a_lower} Details="{d3}"',
        f'[{date}T{h2:02d}:56:10Z] User=u8 Action=Restart Target={target_a_lower} Details="{d3}"',
        f'[{date}T{h1:02d}:30:11Z] User=u9 Action=Update Target=/tmp/{token} Details="lines_added: 0" trailing-junk',
        ''
    ])


def test_submitted_program_on_unseen_inputs():
    original_log = open(LOG_PATH, 'rb').read() if os.path.exists(LOG_PATH) else None
    original_csv = open(CSV_PATH, 'rb').read() if os.path.exists(CSV_PATH) else None
    try:
        for case_number in range(3):
            dynamic_log = make_dynamic_log(case_number)
            with open(LOG_PATH, 'w', encoding='utf-8') as f:
                f.write(dynamic_log)
            expected = parse_and_process_log(LOG_PATH)
            assert expected, "Internal dynamic test case unexpectedly produced no rows."

            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
            result = subprocess.run(
                [BINARY_PATH], cwd="/home/user",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=10
            )
            assert result.returncode == 0, \
                f"tracker failed on an unseen input (exit {result.returncode}):\n{result.stderr}"
            read_and_check_csv(expected)
    finally:
        if original_log is None:
            if os.path.exists(LOG_PATH):
                os.remove(LOG_PATH)
        else:
            with open(LOG_PATH, 'wb') as f:
                f.write(original_log)
        if original_csv is None:
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
        else:
            with open(CSV_PATH, 'wb') as f:
                f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
